import vulkan, vulkan_wrapper, std/sequtils, renderdoc

proc getLayers*(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_LAYER_KHRONOS_validation")

proc getExtensions*(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)

proc createInstance*(appName, engineName: cstring,
                     layers, extensions: openarray[cstring],
                     apiVersion = vkApiVersion1_3.uint32): VkInstance =
  # Create an ApplicationInfo struct
  let applicationInfo = newVkApplicationInfo(
    pApplicationName = appName,
    applicationVersion = 1,
    pEngineName = engineName,
    engineVersion = 1,
    apiVersion = apiVersion
  )
  when defined(vkDebug):
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
  # Create a Vulkan instance
  let instanceCreateInfo = newVkInstanceCreateInfo(
    pNext = when defined(vkDebug): addr features else: nil,
    pApplicationInfo = applicationInfo.addr,
    pEnabledLayerNames = layers,
    pEnabledExtensionNames = extensions
  )
  result = createInstance(instanceCreateInfo)

proc debugCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                   messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                   pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT,
                   pUserData: pointer): VkBool32 {.cdecl.} =
  stderr.writeLine(pCallbackData.pMessage)
  return false.VkBool32

proc setupDebugUtilsMessenger*(instance: VkInstance): VkDebugUtilsMessengerEXT =
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
  result = createDebugUtilsMessengerEXT(instance, createInfo)

proc findPhysicalDevice*(instance: VkInstance): VkPhysicalDevice =
  # Enumerate physical devices
  let physicalDevices = enumeratePhysicalDevices(instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  # We simply choose the first available physical device.
  result = physicalDevices[0]

proc getComputeQueueFamilyIndex*(physicalDevice: VkPhysicalDevice): uint32 =
  # Find a compute queue family
  let queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0 ..< queueFamilyProperties.len:
    let property = queueFamilyProperties[i]
    if property.queueCount > 0 and
        VkQueueFlagBits.ComputeBit in property.queueFlags:
      return i.uint32
  assert false, "Could not find a queue family that supports operations"

proc createDevice*(physicalDevice: VkPhysicalDevice,
                   queueFamilyIndex: uint32,
                   layers, extensions: openarray[cstring],
                   physicalDeviceFeatures: openarray[VkPhysicalDeviceFeatures],
                   pNext: pointer = nil): VkDevice =
  let queuePriority: array[1, float32] = [1.0]
  let deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = queueFamilyIndex,
    queuePriorities = queuePriority
  )
  let deviceCreateInfo = newVkDeviceCreateInfo(
    pNext = pNext,
    queueCreateInfos = [deviceQueueCreateInfo],
    pEnabledLayerNames = layers,
    pEnabledExtensionNames = extensions,
    enabledFeatures = physicalDeviceFeatures
  )
  # Create a logical device
  result = createDevice(physicalDevice, deviceCreateInfo)

proc findMemoryType*(physicalDevice: VkPhysicalDevice,
                     typeFilter: uint32,
                     size: VkDeviceSize,
                     properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  let memoryProperties = getPhysicalDeviceMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
        memoryType.propertyFlags >= properties and
        size <= memoryProperties.memoryHeaps[memoryType.heapIndex].size:
      return i.uint32
  assert false, "Failed to find suitable memory type"

proc createBuffer*(device: VkDevice, physicalDevice: VkPhysicalDevice,
                   size: VkDeviceSize, usage: VkBufferUsageFlags,
                   properties: VkMemoryPropertyFlags): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferCreateInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = []
  )
  let buffer = createBuffer(device, bufferCreateInfo)
  # Memory requirements
  let bufferMemoryRequirements = getBufferMemoryRequirements(device, buffer)
  # Allocate memory for the buffer
  let allocInfo = newVkMemoryAllocateInfo(
    allocationSize = bufferMemoryRequirements.size,
    memoryTypeIndex = findMemoryType(physicalDevice, bufferMemoryRequirements.memoryTypeBits,
                                     bufferMemoryRequirements.size, properties)
  )
  let bufferMemory = allocateMemory(device, allocInfo)
  # Bind the memory to the buffer
  bindBufferMemory(device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc createDescriptorSetLayout*(device: VkDevice,
                                bindings: openarray[VkDescriptorSetLayoutBinding]): VkDescriptorSetLayout =
  let createInfo = newVkDescriptorSetLayoutCreateInfo(
    bindings = bindings
  )
  result = createDescriptorSetLayout(device, createInfo)

proc createDescriptorPool*(device: VkDevice,
                           bufferInfos: openarray[(VkBuffer, VkDeviceSize, VkDescriptorType)]): VkDescriptorPool =
  var poolSizes: seq[VkDescriptorPoolSize] = @[]
  for (_, _, descriptorType) in bufferInfos:
    poolSizes.add newVkDescriptorPoolSize(
      `type` = descriptorType,
      descriptorCount = 1
    )
  let descriptorPoolCreateInfo = newVkDescriptorPoolCreateInfo(
    maxSets = 1,
    poolSizes = poolSizes
  )
  result = createDescriptorPool(device, descriptorPoolCreateInfo)

proc createDescriptorSets*(device: VkDevice, descriptorPool: VkDescriptorPool,
                           setLayout: VkDescriptorSetLayout,
                           bufferInfos: openarray[(VkBuffer, VkDeviceSize, VkDescriptorType)]): seq[VkDescriptorSet] =
  # Allocate descriptor sets
  let descriptorSetAllocateInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = descriptorPool,
    setLayouts = [setLayout]
  )
  let descriptorSet = allocateDescriptorSets(device, descriptorSetAllocateInfo)
  result = @[descriptorSet]
  # Create write descriptor sets
  var descriptorBufferInfos: seq[VkDescriptorBufferInfo] = @[]
  for i, (buffer, size, _) in bufferInfos:
    let descriptorBufferInfo = newVkDescriptorBufferInfo(
      buffer = buffer,
      offset = 0.VkDeviceSize,
      range = size
    )
    descriptorBufferInfos.add(descriptorBufferInfo)
  var writeDescriptorSets: seq[VkWriteDescriptorSet] = @[]
  for i, (_, _, descriptorType) in bufferInfos:
    let writeDescriptorSet = newVkWriteDescriptorSet(
      dstSet = result[0],
      dstBinding = i.uint32,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = descriptorType,
      pImageInfo = nil,
      pBufferInfo = addr descriptorBufferInfos[i],
      pTexelBufferView = nil
    )
    writeDescriptorSets.add(writeDescriptorSet)
  updateDescriptorSets(device, writeDescriptorSets, [])

proc createShaderModule*(device: VkDevice,
                         shaderSPV: string): VkShaderModule =
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    code = shaderSPV
  )
  result = createShaderModule(device, shaderModuleCreateInfo)

proc createPipelineLayout*(device: VkDevice,
                           descriptorSetLayout: VkDescriptorSetLayout): VkPipelineLayout =
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [descriptorSetLayout],
    pushConstantRanges = []
  )
  result = createPipelineLayout(device, pipelineLayoutCreateInfo)

proc createComputePipeline*(device: VkDevice,
                            computeShaderModule: VkShaderModule,
                            pipelineLayout: VkPipelineLayout,
                            specializationEntries: openarray[VkSpecializationMapEntry],
                            specializationData: pointer,
                            dataSize: uint): VkPipeline =
  let specializationInfo = newVkSpecializationInfo(
    mapEntries = specializationEntries,
    dataSize = dataSize,
    pData = specializationData
  )
  let shaderStageCreateInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = computeShaderModule,
    pName = "main",
    pSpecializationInfo = addr specializationInfo
  )
  let createInfos = [
    newVkComputePipelineCreateInfo(
      stage = shaderStageCreateInfo,
      layout = pipelineLayout,
      basePipelineHandle = VkPipeline(0),
      basePipelineIndex = -1
    )
  ]
  result = createComputePipelines(device, VkPipelineCache(0), createInfos)
  # Clean up shader module
  destroyShaderModule(device, computeShaderModule)

proc createCommandPool*(device: VkDevice, queueFamilyIndex: uint32): VkCommandPool =
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = queueFamilyIndex
  )
  result = createCommandPool(device, commandPoolCreateInfo)

proc allocateCommandBuffer*(device: VkDevice, commandPool: VkCommandPool): VkCommandBuffer =
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )
  result = allocateCommandBuffers(device, commandBufferAllocateInfo)

proc recordCommandBuffer*(commandBuffer: VkCommandBuffer,
                          pipeline: VkPipeline,
                          pipelineLayout: VkPipelineLayout,
                          descriptorSets: openarray[VkDescriptorSet],
                          groupCountX, groupCountY, groupCountZ: uint32 = 1) =
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(OneTimeSubmitBit),
    pInheritanceInfo = nil
  )
  beginCommandBuffer(commandBuffer, commandBufferBeginInfo)
  # Bind the compute pipeline
  cmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, pipeline)
  # Bind the descriptor set
  cmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.Compute,
                        pipelineLayout, 0, descriptorSets, [])
  # Dispatch the compute work
  cmdDispatch(commandBuffer, groupCountX, groupCountY, groupCountZ)
  # End recording the command buffer
  endCommandBuffer(commandBuffer)

proc submitCommandBuffer*(device: VkDevice, queue: VkQueue,
                          commandBuffer: VkCommandBuffer, instance: VkInstance) =
  let submitInfos = [
    newVkSubmitInfo(
      waitSemaphores = [],
      waitDstStageMask = [],
      commandBuffers = [commandBuffer],
      signalSemaphores = []
    )
  ]
  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo()
  let fence = createFence(device, fenceCreateInfo)
  when defined(useRenderDoc): startFrameCapture(instance)
  # Submit the command buffer
  queueSubmit(queue, submitInfos, fence)
  when defined(useRenderDoc): endFrameCapture(instance)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  waitForFence(device, fence, true.VkBool32, high(uint64))
  destroyFence(device, fence)
