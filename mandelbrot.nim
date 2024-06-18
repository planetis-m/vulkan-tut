# https://youtu.be/1BMGTyIF5dI
import vulkan, vulkan_wrapper, std/[sequtils, math], chroma

type
  MandelbrotGenerator* = object
    width, height: int32
    workgroupSize: WorkgroupSize
    instance: VkInstance
    physicalDevice: VkPhysicalDevice
    device: VkDevice
    queue: VkQueue
    queueFamilyIndex: uint32
    storageBuffer: VkBuffer
    storageBufferMemory: VkDeviceMemory
    uniformBuffer: VkBuffer
    uniformBufferMemory: VkDeviceMemory
    descriptorSetLayout: VkDescriptorSetLayout
    descriptorPool: VkDescriptorPool
    descriptorSets: seq[VkDescriptorSet]
    pipelineLayout: VkPipelineLayout
    pipeline: VkPipeline
    commandPool: VkCommandPool
    commandBuffer: VkCommandBuffer
    when defined(vkDebug):
      debugUtilsMessenger: VkDebugUtilsMessengerEXT

  WorkgroupSize = object
    x, y: uint32

proc cleanup(x: MandelbrotGenerator) =
  # Clean up
  vkFreeMemory(x.device, x.uniformBufferMemory, nil)
  vkDestroyBuffer(x.device, x.uniformBuffer, nil)
  vkFreeMemory(x.device, x.storageBufferMemory, nil)
  vkDestroyBuffer(x.device, x.storageBuffer, nil)
  vkDestroyPipeline(x.device, x.pipeline, nil)
  vkDestroyPipelineLayout(x.device, x.pipelineLayout, nil)
  vkDestroyDescriptorPool(x.device, x.descriptorPool, nil)
  vkDestroyDescriptorSetLayout(x.device, x.descriptorSetLayout, nil)
  vkDestroyCommandPool(x.device, x.commandPool, nil)
  vkDestroyDevice(x.device, nil)
  when defined(vkDebug):
    vkDestroyDebugUtilsMessengerEXT(x.instance, x.debugUtilsMessenger, nil)
  vkDestroyInstance(x.instance, nil)

proc newMandelbrotGenerator*(width, height: int32): MandelbrotGenerator =
  ## Create a generator with the width and the height of the image.
  result = MandelbrotGenerator(
    width: width,
    height: height,
    workgroupSize: WorkgroupSize(x: 32, y: 32)
  )

proc fetchRenderedImage(x: MandelbrotGenerator): seq[ColorRGBA] =
  let count = x.width*x.height
  let mappedMemory = mapMemory(x.device, x.storageBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(Color)*count), 0.VkMemoryMapFlags)
  let data = cast[ptr UncheckedArray[Color]](mappedMemory)
  result = newSeq[ColorRGBA](count)
  # Transform data from [0.0f, 1.0f] (float) to [0, 255] (uint8).
  for i in 0..result.high:
    result[i] = rgba(data[i])
  vkUnmapMemory(x.device, x.storageBufferMemory)

proc getLayers(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_LAYER_KHRONOS_validation")

proc getExtensions(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)

template toCStringArray(x: seq[cstring]): untyped =
  if x.len == 0: nil else: cast[cstringArray](addr x[0])

proc createInstance(x: var MandelbrotGenerator) =
  # Create an ApplicationInfo struct
  let applicationInfo = newVkApplicationInfo(
    pApplicationName = "Mandelbrot",
    applicationVersion = vkMakeVersion(0, 1, 0, 0),
    pEngineName = "No Engine",
    engineVersion = vkMakeVersion(0, 1, 0, 0),
    apiVersion = vkApiVersion1_1
  )
  when defined(vkDebug):
    # Enable the Khronos validation layer
    let layerProperties = enumerateInstanceLayerProperties()
    let foundValidationLayer = layerProperties.anyIt(
        "VK_LAYER_KHRONOS_validation" == cast[cstring](it.layerName.addr))
    assert foundValidationLayer, "Validation layer required, but not available"
  # Create a Vulkan instance
  let layers = getLayers()
  let extensions = getExtensions()
  let instanceCreateInfo = newVkInstanceCreateInfo(
    pApplicationInfo = applicationInfo.addr,
    enabledLayerCount = uint32(layers.len),
    ppEnabledLayerNames = layers.toCStringArray,
    enabledExtensionCount = uint32(extensions.len),
    ppEnabledExtensionNames = extensions.toCStringArray
  )
  x.instance = createInstance(instanceCreateInfo)

proc findPhysicalDevice(x: var MandelbrotGenerator) =
  # Enumerate physical devices
  let physicalDevices = enumeratePhysicalDevices(x.instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  # We simply choose the first available physical device.
  x.physicalDevice = physicalDevices[0]

proc getComputeQueueFamilyIndex(physicalDevice: VkPhysicalDevice): uint32 =
  # Find a compute queue family
  let queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0 ..< queueFamilyProperties.len:
    let property = queueFamilyProperties[i]
    if property.queueCount > 0 and
        (property.queueFlags.uint32 and VkQueueFlagBits.ComputeBit.uint32) != 0:
      return i.uint32
  assert false, "Could not find a queue family that supports operations"

proc createDevice(x: var MandelbrotGenerator) =
  x.queueFamilyIndex = getComputeQueueFamilyIndex(x.physicalDevice)
  let queuePriority = 1.0'f32
  let queueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = x.queueFamilyIndex,
    queueCount = 1,
    pQueuePriorities = queuePriority.addr
  )
  let layers = getLayers()
  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfoCount = 1,
    pQueueCreateInfos = queueCreateInfo.addr,
    enabledLayerCount = uint32(layers.len),
    ppEnabledLayerNames = layers.toCStringArray,
    enabledExtensionCount = 0,
    ppEnabledExtensionNames = nil,
    pEnabledFeatures = nil
  )
  # Create a logical device
  x.device = createDevice(x.physicalDevice, deviceCreateInfo)
  # Get the compute queue
  x.queue = getDeviceQueue(x.device, x.queueFamilyIndex, 0)

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
    size: VkDeviceSize, properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  let memoryProperties = getMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
        (memoryType.propertyFlags.uint32 and properties.uint32) == properties.uint32 and
        size.uint64 <= memoryProperties.memoryHeaps[memoryType.heapIndex].size.uint64:
      return i.uint32
  assert false, "Failed to find suitable memory type"

proc createBuffer(x: MandelbrotGenerator, size: VkDeviceSize, usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferCreateInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndexCount = 0,
    pQueueFamilyIndices = nil
  )
  let buffer = createBuffer(x.device, bufferCreateInfo)
  # Memory requirements
  let bufferMemoryRequirements = getBufferMemoryRequirements(x.device, buffer)
  # Allocate memory for the buffer
  let allocInfo = newVkMemoryAllocateInfo(
    allocationSize = bufferMemoryRequirements.size,
    memoryTypeIndex = findMemoryType(x.physicalDevice, bufferMemoryRequirements.memoryTypeBits,
        bufferMemoryRequirements.size, properties)
  )
  let bufferMemory = allocateMemory(x.device, allocInfo)
  # Bind the memory to the buffer
  bindBufferMemory(x.device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc createBuffers(x: var MandelbrotGenerator) =
  # Allocate memory for both buffers
  (x.storageBuffer, x.storageBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(float32)*4*x.width*x.height),
    VkBufferUsageFlags{VkBufferUsageFlagBits.StorageBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit})
  (x.uniformBuffer, x.uniformBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(int32)*2),
    VkBufferUsageFlags{VkBufferUsageFlagBits.UniformBufferBit},
    VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit})
  # Map the memory and write to the uniform buffer
  let mappedMemory = mapMemory(x.device, x.uniformBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(int32)*2), 0.VkMemoryMapFlags)
  let ubo = [x.width.int32, x.height.int32]
  copyMem(mappedMemory, ubo.addr, sizeof(int32)*2)
  vkUnmapMemory(x.device, x.uniformBufferMemory)

proc createDescriptorSetLayout(x: var MandelbrotGenerator) =
  # Define the descriptor set layout bindings
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
  # Create a descriptor set layout
  let createInfo = newVkDescriptorSetLayoutCreateInfo(
    bindingCount = bindings.len.uint32,
    pBindings = bindings[0].addr
  )
  x.descriptorSetLayout = createDescriptorSetLayout(x.device, createInfo)

proc createDescriptorSets(x: var MandelbrotGenerator) =
  # Create a descriptor pool
  let descriptorPoolSizes = [
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.StorageBuffer,
      descriptorCount = 1
    ),
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.UniformBuffer,
      descriptorCount = 1
    )
  ]
  let descriptorPoolCreateInfo = newVkDescriptorPoolCreateInfo(
    maxSets = 2,
    poolSizeCount = descriptorPoolSizes.len.uint32,
    pPoolSizes = descriptorPoolSizes[0].addr
  )
  x.descriptorPool = createDescriptorPool(x.device, descriptorPoolCreateInfo)
  # Allocate a descriptor set
  let descriptorSetAllocateInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = x.descriptorPool,
    descriptorSetCount = 1,
    pSetLayouts = x.descriptorSetLayout.addr
  )
  let descriptorSet = allocateDescriptorSets(x.device, descriptorSetAllocateInfo)
  x.descriptorSets = @[descriptorSet]
  # Update the descriptor set with the buffer information
  let descriptorStorageBufferInfo = newVkDescriptorBufferInfo(
    buffer = x.storageBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(float32)*4*x.width*x.height)
  )
  let descriptorUniformBufferInfo = newVkDescriptorBufferInfo(
    buffer = x.uniformBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(int32)*2)
  )
  let writeDescriptorSets = [
    newVkWriteDescriptorSet(
      dstSet = x.descriptorSets[0],
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorStorageBufferInfo.addr,
      pTexelBufferView = nil
    ),
    newVkWriteDescriptorSet(
      dstSet = x.descriptorSets[0],
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorUniformBufferInfo.addr,
      pTexelBufferView = nil
    )
  ]
  updateDescriptorSets(x.device, writeDescriptorSets, [])

proc createComputePipeline(x: var MandelbrotGenerator) =
  # Create the shader module
  let computeShaderCode = readFile("build/shaders/mandelbrot.comp.spv")
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    codeSize = computeShaderCode.len.uint,
    pCode = cast[ptr uint32](computeShaderCode[0].addr)
  )
  let computeShaderModule = createShaderModule(x.device, shaderModuleCreateInfo)
  let specializationMapEntries = [
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
  let specializationInfo = newVkSpecializationInfo(
    mapEntryCount = specializationMapEntries.len.uint32,
    pMapEntries = specializationMapEntries[0].addr,
    dataSize = sizeof(WorkgroupSize).uint,
    pData = x.workgroupSize.addr
  )
  let shaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = computeShaderModule,
    pName = "main",
    pSpecializationInfo = specializationInfo.addr
  )
  # Create a pipeline layout with the descriptor set layout
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayoutCount = 1,
    pSetLayouts = x.descriptorSetLayout.addr,
    pushConstantRangeCount = 0,
    pPushConstantRanges = nil
  )
  x.pipelineLayout = createPipelineLayout(x.device, pipelineLayoutCreateInfo)
  # Create the compute pipeline
  let createInfos = [
    newVkComputePipelineCreateInfo(
      stage = shaderStageCreateInfo,
      layout = x.pipelineLayout,
      basePipelineHandle = 0.VkPipeline,
      basePipelineIndex = -1
    )
  ]
  x.pipeline = createComputePipelines(x.device, 0.VkPipelineCache, createInfos)
  vkDestroyShaderModule(x.device, computeShaderModule, nil)

proc createCommandBuffer(x: var MandelbrotGenerator) =
  # Create a command pool
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = x.queueFamilyIndex
  )
  x.commandPool = createCommandPool(x.device, commandPoolCreateInfo)
  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = x.commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )
  x.commandBuffer = allocateCommandBuffers(x.device, commandBufferAllocateInfo)
  # Begin recording the command buffer
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(VkCommandBufferUsageFlagBits.OneTimeSubmitBit),
    pInheritanceInfo = nil
  )
  beginCommandBuffer(x.commandBuffer, commandBufferBeginInfo)
  # Bind the compute pipeline
  vkCmdBindPipeline(x.commandBuffer, VkPipelineBindPoint.Compute, x.pipeline)
  # Bind the descriptor set
  cmdBindDescriptorSets(x.commandBuffer, VkPipelineBindPoint.Compute, x.pipelineLayout,
      0, x.descriptorSets, [])
  # Dispatch the compute work
  let numWorkgroupX = ceilDiv(x.width.uint32, x.workgroupSize.x)
  let numWorkgroupY = ceilDiv(x.height.uint32, x.workgroupSize.y)
  vkCmdDispatch(x.commandBuffer, numWorkgroupX, numWorkgroupY, 1)
  # End recording the command buffer
  endCommandBuffer(x.commandBuffer)

proc submitCommandBuffer(x: MandelbrotGenerator) =
  let submitInfos = [
    newVkSubmitInfo(
      waitSemaphoreCount = 0,
      pWaitSemaphores = nil,
      pWaitDstStageMask = nil,
      commandBufferCount = 1,
      pCommandBuffers = x.commandBuffer.addr,
      signalSemaphoreCount = 0,
      pSignalSemaphores = nil
    )
  ]
  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo()
  let fence = createFence(x.device, fenceCreateInfo)
  # Submit the command buffer
  queueSubmit(x.queue, submitInfos, fence)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  waitForFence(x.device, fence, VkBool32(true), high(uint64))
  vkDestroyFence(x.device, fence, nil)

when defined(vkDebug):
  proc debugCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                     messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                     pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT,
                     pUserData: pointer): VkBool32 {.cdecl.} =
    stderr.write(pCallbackData.pMessage)
    stderr.write("\n")
    return VkBool32(false)

  proc setupDebugUtilsMessenger(x: var MandelbrotGenerator) =
    let severityFlags = VkDebugUtilsMessageSeverityFlagsEXT{
      VerboseBit, InfoBit, VkDebugUtilsMessageSeverityFlagBitsEXT.WarningBit,
      VkDebugUtilsMessageSeverityFlagBitsEXT.ErrorBit}
    let messageTypeFlags = VkDebugUtilsMessageTypeFlagsEXT{
      GeneralBit, VkDebugUtilsMessageTypeFlagBitsEXT.ValidationBit, PerformanceBit}
    let createInfo = newVkDebugUtilsMessengerCreateInfoEXT(
      messageSeverity = severityFlags,
      messageType = messageTypeFlags,
      pfnUserCallback = debugCallback
    )
    x.debugUtilsMessenger = createDebugUtilsMessengerEXT(x.instance, createInfo)

proc generate*(x: var MandelbrotGenerator): seq[ColorRGBA] =
  ## Return the raw data of a mandelbrot image.
  try:
    vkPreload()
    # Hardware Setup Stage
    createInstance(x)
    vkInit(x.instance, load1_2 = false, load1_3 = false)
    when defined(vkDebug):
      loadVkExtDebugUtils()
      setupDebugUtilsMessenger(x)
    findPhysicalDevice(x)
    createDevice(x)
    # Resource Setup Stage
    createBuffers(x)
    # Pipeline Setup Stage
    createDescriptorSetLayout(x)
    createDescriptorSets(x)
    createComputePipeline(x)
    # Command Execution Stage
    createCommandBuffer(x)
    submitCommandBuffer(x)
    # Fetch data from VRAM to RAM.
    result = fetchRenderedImage(x)
  finally:
    cleanup(x)
