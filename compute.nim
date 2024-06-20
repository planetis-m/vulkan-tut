import vulkan, vulkan_wrapper, std/[strutils, times, sequtils, math], renderdoc

const
  NumElements = 128
  WorkGroupSize = 32 # This should match your shader's local workgroup size

template toCString(arr: openarray[char]): untyped = cast[cstring](addr arr[0])

proc alignUp(value, alignment: VkDeviceSize): VkDeviceSize {.inline.} =
  (value + alignment - 1.VkDeviceSize) and not (alignment - 1.VkDeviceSize)

proc getComputeQueueFamilyIndex(physicalDevice: VkPhysicalDevice): uint32 =
  # Find a compute queue family
  let queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0 ..< queueFamilyProperties.len:
    let property = queueFamilyProperties[i]
    if property.queueCount > 0 and
        VkQueueFlagBits.ComputeBit in property.queueFlags:
      return i.uint32
  assert false, "Could not find a queue family that supports operations"

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
    size: VkDeviceSize, properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  let memoryProperties = getPhysicalDeviceMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
        memoryType.propertyFlags >= properties and
        size <= memoryProperties.memoryHeaps[memoryType.heapIndex].size:
      return i.uint32
  assert false, "Failed to find suitable memory type"

proc main =
  vkPreload()
  # Create an ApplicationInfo struct
  let appInfo = newVkApplicationInfo(
    pApplicationName = "VulkanCompute",
    applicationVersion = 1,
    pEngineName = nil,
    engineVersion = 0,
    apiVersion = vkApiVersion1_3
  )
  # Enable the Khronos validation layer
  let layerProperties = enumerateInstanceLayerProperties()
  let foundValidationLayer = layerProperties.anyIt(
      "VK_LAYER_KHRONOS_validation" == cast[cstring](it.layerName.addr))
  assert foundValidationLayer, "Validation layer required, but not available"
  # Shader printf is a feature of the validation layers that needs to be enabled
  let features = newVkValidationFeaturesEXT(
    enabledValidationFeatures = [VkValidationFeatureEnableEXT.DebugPrintf],
    disabledValidationFeatures = []
  )
  let enabledLayerNames = [cstring"VK_LAYER_KHRONOS_validation"]
  # Create a Vulkan instance
  let instanceCreateInfo = newVkInstanceCreateInfo(
    pNext = addr features,
    pApplicationInfo = addr appInfo,
    pEnabledLayerNames = [cstring"VK_LAYER_KHRONOS_validation"],
    pEnabledExtensionNames = [VK_EXT_DEBUG_UTILS_EXTENSION_NAME.cstring]
  )
  let instance = createInstance(instanceCreateInfo)
  vkInit(instance, load1_2 = false, load1_3 = false)
  # Enumerate physical devices
  let physicalDevices = enumeratePhysicalDevices(instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  # Use the first physical device
  let physicalDevice = physicalDevices[0]
  # Get device properties
  let deviceProperties = getPhysicalDeviceProperties(physicalDevice)

  echo "Selected physical device: ", deviceProperties.deviceName.toCString
  echo "API version: ", vkVersionMajor(deviceProperties.apiVersion), ".", vkVersionMinor(deviceProperties.apiVersion), ".", vkVersionPatch(deviceProperties.apiVersion)
  echo "Max compute shared memory size: ", formatSize(deviceProperties.limits.maxComputeSharedMemorySize.int64)

  let computeQueueFamilyIndex = getComputeQueueFamilyIndex(physicalDevice)
  echo "Compute Queue Family Index: ", computeQueueFamilyIndex

  let queueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = computeQueueFamilyIndex,
    queuePriorities = [1.0'f32]
  )
  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfos = [queueCreateInfo],
    pEnabledLayerNames = [],
    pEnabledExtensionNames = [],
    enabledFeatures = []
  )
  # Create a logical device
  let device = createDevice(physicalDevice, deviceCreateInfo)
  # Create buffers
  let bufferSize = VkDeviceSize(NumElements*sizeof(int32))

  let bufferCreateInfo = newVkBufferCreateInfo(
    size = bufferSize,
    usage = VkBufferUsageFlags(VkBufferUsageFlagBits.StorageBufferBit),
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [computeQueueFamilyIndex]
  )
  let inBuffer = createBuffer(device, bufferCreateInfo)
  let outBuffer = createBuffer(device, bufferCreateInfo)
  # Memory req
  let inMemRequirements = getBufferMemoryRequirements(device, inBuffer)
  let outMemRequirements = getBufferMemoryRequirements(device, outBuffer)
  # Determine the size and alignment for the combined memory
  let alignedSize = alignUp(inMemRequirements.size, outMemRequirements.alignment)
  let combinedSize = alignedSize + outMemRequirements.size

  let properties = VkMemoryPropertyFlags{HostCoherentBit, HostVisibleBit}
  assert inMemRequirements.memoryTypeBits == outMemRequirements.memoryTypeBits
  let memTypeIndex = findMemoryType(physicalDevice, inMemRequirements.memoryTypeBits,
                                    combinedSize, properties)
  echo "Memory Type Index: ", memTypeIndex

  # Allocate memory for both buffers
  let memAllocateInfo = newVkMemoryAllocateInfo(
    allocationSize = combinedSize,
    memoryTypeIndex = memTypeIndex
  )
  let bufferMemory = allocateMemory(device, memAllocateInfo)
  # Map the memory and write to the input buffer
  var inBufferPtr: ptr array[NumElements, int32] = nil
  let mappedMemory = mapMemory(device, bufferMemory, 0.VkDeviceSize, bufferSize, 0.VkMemoryMapFlags)
  let inData = cast[ptr UncheckedArray[int32]](mappedMemory)
  for i in 0 ..< NumElements:
    inData[i] = int32(i)
  unmapMemory(device, bufferMemory)

  # Bind the memory to the input buffer
  bindBufferMemory(device, inBuffer, bufferMemory, 0.VkDeviceSize)
  # Bind the memory to the output buffer at the aligned offset
  bindBufferMemory(device, outBuffer, bufferMemory, alignedSize)

  # Create a VkShaderModuleCreateInfo struct
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    code = readFile("build/shaders/square.comp.spv")
  )
  # Create the shader module
  let shaderModule = createShaderModule(device, shaderModuleCreateInfo)

  # Define the descriptor set layout bindings
  let descriptorSetLayoutBindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0, # Binding number 0: Input buffer
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit),
      pImmutableSamplers = nil
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1, # Binding number 1: Output buffer
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit),
      pImmutableSamplers = nil
    )
  ]
  # Create a descriptor set layout
  let descriptorSetLayoutCreateInfo = newVkDescriptorSetLayoutCreateInfo(
    bindings = descriptorSetLayoutBindings
  )
  let descriptorSetLayout = createDescriptorSetLayout(device, descriptorSetLayoutCreateInfo)
  # Create a pipeline layout with the descriptor set layout
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [descriptorSetLayout],
    pushConstantRanges = []
  )
  let pipelineLayout = createPipelineLayout(device, pipelineLayoutCreateInfo)
  # Create the compute pipeline
  let pipelineCreateInfo = newVkComputePipelineCreateInfo(
    stage = newVkPipelineShaderStageCreateInfo(
      stage = VkShaderStageFlagBits.ComputeBit,
      module = shaderModule,
      pName = "main", # Entry point of the shader
      pSpecializationInfo = nil
    ),
    layout = pipelineLayout,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1
  )
  let computePipeline = createComputePipelines(device, 0.VkPipelineCache, [pipelineCreateInfo])
  # Create a descriptor pool
  let poolSize = newVkDescriptorPoolSize(
    `type` = VkDescriptorType.StorageBuffer,
    descriptorCount = 2 # One for the input buffer and one for the output buffer
  )
  let descriptorPoolCreateInfo = newVkDescriptorPoolCreateInfo(
    maxSets = 1, # We only need one set
    poolSizes = [poolSize]
  )
  let descriptorPool = createDescriptorPool(device, descriptorPoolCreateInfo)
  # Allocate a descriptor set
  let allocInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = descriptorPool,
    setLayouts = [descriptorSetLayout]
  )
  let descriptorSet = allocateDescriptorSets(device, allocInfo)
  # Update the descriptor set with the buffer information
  let descriptorBufferInfo = [
    newVkDescriptorBufferInfo(
      buffer = inBuffer,
      offset = 0.VkDeviceSize,
      range = bufferSize
    ),
    newVkDescriptorBufferInfo(
      buffer = outBuffer,
      offset = 0.VkDeviceSize,
      range = bufferSize
    )
  ]
  let writeDescriptorSet = [
    newVkWriteDescriptorSet(
      dstSet = descriptorSet,
      dstBinding = 0, # Input buffer
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorBufferInfo[0].addr,
      pTexelBufferView = nil
    ),
    newVkWriteDescriptorSet(
      dstSet = descriptorSet,
      dstBinding = 1, # Output buffer
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = descriptorBufferInfo[1].addr,
      pTexelBufferView = nil
    )
  ]
  updateDescriptorSets(device, writeDescriptorSet, [])
  # Create a command pool
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    flags = VkCommandPoolCreateFlags(VkCommandPoolCreateFlagBits.ResetCommandBufferBit),
    queueFamilyIndex = computeQueueFamilyIndex
  )
  let commandPool = createCommandPool(device, commandPoolCreateInfo)
  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )
  let commandBuffer = allocateCommandBuffers(device, commandBufferAllocateInfo)
  # Begin recording the command buffer
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(VkCommandBufferUsageFlagBits.OneTimeSubmitBit),
    pInheritanceInfo = nil
  )
  beginCommandBuffer(commandBuffer, commandBufferBeginInfo)
  # Bind the compute pipeline
  cmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, computePipeline)
  # Bind the descriptor set
  cmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.Compute, pipelineLayout,
      0, [descriptorSet], [])
  # Dispatch the compute work
  let numGroupsX = ceilDiv(NumElements, WorkGroupSize).uint32
  cmdDispatch(commandBuffer, numGroupsX, 1, 1)
  # End recording the command buffer
  endCommandBuffer(commandBuffer)
  # Submit the command buffer to the queue
  let submitInfo = newVkSubmitInfo(
    waitSemaphores = [],
    waitDstStageMask = [],
    commandBuffers = [commandBuffer],
    signalSemaphores = []
  )
  # Get the compute queue
  let computeQueue = getDeviceQueue(device, computeQueueFamilyIndex, 0)
  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo(
    flags = 0.VkFenceCreateFlags # Initially unsignaled
  )
  let fence = createFence(device, fenceCreateInfo)
  let t0 = cpuTime()
  when defined(useRenderDoc): startFrameCapture(instance)
  # Submit the command buffer
  queueSubmit(computeQueue, [submitInfo], fence)
  when defined(useRenderDoc): endFrameCapture(instance)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  waitForFence(device, fence, true.VkBool32, high(uint64))
  let t1 = cpuTime()
  # Map the output buffer to read the results
  let outBufferPtr = mapMemory(device, bufferMemory, alignedSize, bufferSize, 0.VkMemoryMapFlags)
  let t2 = cpuTime()
  let outData = cast[ptr UncheckedArray[int32]](outBufferPtr)
  # echo "OUTPUT: ", outBufferPtr[]
  for i in 0 ..< NumElements:
    doAssert outData[i] == int32(i*i)
  let t3 = cpuTime()
  unmapMemory(device, bufferMemory)

  template ff(f: float, prec: int = 4): string =
   formatFloat(f*1000, ffDecimal, prec) # ms

  echo "Process: ", ff(t1-t0), " Map: ", ff(t2-t1), " Read: ", ff(t3-t2)

  # Clean up
  destroyFence(device, fence)
  destroyCommandPool(device, commandPool)
  destroyDescriptorPool(device, descriptorPool)
  destroyPipeline(device, computePipeline)
  destroyPipelineLayout(device, pipelineLayout)
  destroyDescriptorSetLayout(device, descriptorSetLayout)
  destroyShaderModule(device, shaderModule)
  freeMemory(device, bufferMemory)
  destroyBuffer(device, inBuffer)
  destroyBuffer(device, outBuffer)
  destroyDevice(device)
  destroyInstance(instance)

main()
