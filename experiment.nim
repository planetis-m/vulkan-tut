import vulkan, vulkan_wrapper, vulkan_functions,
  std/[os, math], pixie/fileformats/qoi, chroma, renderdoc

type
  WorkgroupSize = object
    x, y: uint32

proc updateUniformBuffer(device: VkDevice, memory: VkDeviceMemory, data: pointer,
                          dataSize: VkDeviceSize) =
  let mappedMemory = mapMemory(device, memory, 0.VkDeviceSize, dataSize, 0.VkMemoryMapFlags)
  copyMem(mappedMemory, data, dataSize.int)
  unmapMemory(device, memory)

proc fetchRenderedImage(device: VkDevice, memory: VkDeviceMemory, size: VkDeviceSize,
                        count: int): seq[ColorRGBA] =
  let mappedMemory = mapMemory(device, memory, 0.VkDeviceSize, size, 0.VkMemoryMapFlags)
  let data = cast[ptr UncheckedArray[Color]](mappedMemory)
  result = newSeq[ColorRGBA](count)
  # Transform data from [0.0f, 1.0f] (float) to [0, 255] (uint8).
  for i in 0..result.high:
    result[i] = rgba(data[i])
  unmapMemory(device, memory)

proc main =
  let width, height = 1024
  let layers = getLayers()
  let extensions = getExtensions()
  vkPreload()
  let instance = createInstance("MyApp", "MyEngine", layers, extensions)
  vkInit(instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
    loadVkExtDebugUtils()
    let debugUtilsMessenger = setupDebugUtilsMessenger(instance)
  when defined(useRenderDoc):
    rDocInit()
  let physicalDevice = findPhysicalDevice(instance)
  let queueFamilyIndex = getComputeQueueFamilyIndex(physicalDevice)
  let device = createDevice(physicalDevice, queueFamilyIndex, layers, [], [])

  let storageSize = VkDeviceSize(sizeof(float32) * 4 * width * height)
  let uniformSize = VkDeviceSize(sizeof(int32) * 2)
  # Create buffers
  let (storageBuffer, storageBufferMemory) = createBuffer(
    device, physicalDevice, storageSize,
    VkBufferUsageFlags{VkBufferUsageFlagBits.StorageBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit}
  )
  let (uniformBuffer, uniformBufferMemory) = createBuffer(
    device, physicalDevice, storageSize,
    VkBufferUsageFlags{VkBufferUsageFlagBits.UniformBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit}
  )
  # Map the memory and write to the uniform buffer
  let ubo = [width.int32, height.int32]
  updateUniformBuffer(device, uniformBufferMemory, ubo.addr, uniformSize)

  # Create descriptor set layout
  let bindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0,
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit),
      pImmutableSamplers = nil
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit),
      pImmutableSamplers = nil
    )
  ]
  let descriptorSetLayout = createDescriptorSetLayout(device, bindings)

  let bufferInfos = [
    (storageBuffer, storageSize, VkDescriptorType.StorageBuffer),
    (uniformBuffer, uniformSize, VkDescriptorType.UniformBuffer)
  ]
  # Create descriptor pool
  let descriptorPool = createDescriptorPool(device, bufferInfos)

  # Create and update descriptor sets
  let descriptorSets = createDescriptorSets(device, descriptorPool, descriptorSetLayout, bufferInfos)

  let queue = getDeviceQueue(device, queueFamilyIndex, 0)
  let specializationEntries = [
    newVkSpecializationMapEntry(
      constantID = 0,
      offset = offsetOf(WorkgroupSize, x).uint32,
      size = sizeof(uint32).uint
    ),
    newVkSpecializationMapEntry(
      constantID = 1,
      offset = offsetOf(WorkgroupSize, y).uint32,
      size = sizeof(uint32).uint
    )
  ]
  let workgroupSize = WorkgroupSize(x: 32, y: 32)
  let dataSize = sizeof(WorkgroupSize).uint
  let shaderSPV = readFile("build/shaders/mandelbrot.comp.spv")

  let computeShaderModule = createShaderModule(device, shaderSPV)
  let pipelineLayout = createPipelineLayout(device, [descriptorSetLayout])
  let pipeline = createComputePipeline(device, computeShaderModule, pipelineLayout,
                                      specializationEntries, addr(workgroupSize), dataSize)

  # Clean up shader module
  destroyShaderModule(device, computeShaderModule)
  # Create command pool
  let commandPool = createCommandPool(device, queueFamilyIndex)

  # Allocate command buffer
  let commandBuffer = allocateCommandBuffer(device, commandPool)

  # Record command buffer
  recordCommandBuffer(
    commandBuffer = commandBuffer,
    pipeline = pipeline,
    pipelineLayout = pipelineLayout,
    descriptorSets = descriptorSets,
    groupCountX = ceilDiv(width.uint32, workgroupSize.x),
    groupCountY = ceilDiv(height.uint32, workgroupSize.y)
  )
  # Submit command buffer
  submitCommandBuffer(
    device = device,
    queue = queue,
    commandBuffer = commandBuffer,
    instance = instance
  )

  let result = fetchRenderedImage(device, storageBufferMemory, storageSize, width * height)
  let qoi = Qoi(data: result, width: width, height: height, channels: 4)
  let str = encodeQoi(qoi)
  writeFile("mandelbrot.qoi", str)

  # Clean up
  freeMemory(device, uniformBufferMemory)
  destroyBuffer(device, uniformBuffer)
  freeMemory(device, storageBufferMemory)
  destroyBuffer(device, storageBuffer)
  destroyPipeline(device, pipeline)
  destroyPipelineLayout(device, pipelineLayout)
  destroyDescriptorPool(device, descriptorPool)
  destroyDescriptorSetLayout(device, descriptorSetLayout)
  destroyCommandPool(device, commandPool)
  destroyDevice(device)
  when defined(vkDebug):
    destroyDebugUtilsMessenger(instance, debugUtilsMessenger)
  destroyInstance(instance)

main()
