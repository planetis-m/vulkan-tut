# https://youtu.be/1BMGTyIF5dI
import vulkan, std/[sequtils, math]

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

template checkVkResult(call: untyped) =
  when defined(danger):
    discard call
  else:
    {.line: instantiationInfo().}:
      assert call == VkSuccess

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

proc fetchRenderedImage(x: MandelbrotGenerator): seq[uint8] =
  let count = 4*x.width*x.height
  var mappedMemory: pointer = nil
  checkVkResult vkMapMemory(x.device, x.storageBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(float32)*count), 0.VkMemoryMapFlags, mappedMemory.addr)
  let data = cast[ptr UncheckedArray[float32]](mappedMemory)
  result = newSeq[uint8](count)
  # Transform data from [0.0f, 1.0f] (float) to [0, 255] (uint8).
  for i in 0 ..< count.int:
    result[i] = uint8(255*data[i])
  vkUnmapMemory(x.device, x.storageBufferMemory)

proc getLayers(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_LAYER_KHRONOS_validation")

proc getExtensions(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_EXT_debug_utils")

template toCStringArray(x: seq[cstring]): untyped =
  if x.len > 0: cast[cstringArray](addr x[0]) else: nil

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
    var layerCount: uint32 = 0
    discard vkEnumerateInstanceLayerProperties(layerCount.addr, nil)
    var layerProperties = newSeq[VkLayerProperties](layerCount)
    discard vkEnumerateInstanceLayerProperties(layerCount.addr, layerProperties[0].addr)
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
  checkVkResult vkCreateInstance(instanceCreateInfo.addr, nil, x.instance.addr)

proc findPhysicalDevice(x: var MandelbrotGenerator) =
  # Enumerate physical devices
  var physicalDeviceCount: uint32 = 0
  discard vkEnumeratePhysicalDevices(x.instance, physicalDeviceCount.addr, nil)
  var physicalDevices = newSeq[VkPhysicalDevice](physicalDeviceCount)
  discard vkEnumeratePhysicalDevices(x.instance, physicalDeviceCount.addr, physicalDevices[0].addr)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  # We simply choose the first available physical device.
  x.physicalDevice = physicalDevices[0]

proc getComputeQueueFamilyIndex(physicalDevice: VkPhysicalDevice): uint32 =
  # Find a compute queue family
  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, nil)
  var queueFamilyProperties = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, queueFamilyProperties[0].addr)
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
  checkVkResult vkCreateDevice(x.physicalDevice, deviceCreateInfo.addr, nil, x.device.addr)
  # Get the compute queue
  vkGetDeviceQueue(x.device, x.queueFamilyIndex, 0, x.queue.addr)

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
    size: VkDeviceSize, properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  var memoryProperties: VkPhysicalDeviceMemoryProperties
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, memoryProperties.addr)
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
  var buffer: VkBuffer
  checkVkResult vkCreateBuffer(x.device, bufferCreateInfo.addr, nil, buffer.addr)
  # Memory requirements
  var bufferMemoryRequirements: VkMemoryRequirements
  vkGetBufferMemoryRequirements(x.device, buffer, bufferMemoryRequirements.addr)
  # Allocate memory for the buffer
  let allocInfo = newVkMemoryAllocateInfo(
    allocationSize = bufferMemoryRequirements.size,
    memoryTypeIndex = findMemoryType(x.physicalDevice, bufferMemoryRequirements.memoryTypeBits,
        bufferMemoryRequirements.size, properties)
  )
  var bufferMemory: VkDeviceMemory
  checkVkResult vkAllocateMemory(x.device, allocInfo.addr, nil, bufferMemory.addr)
  # Bind the memory to the buffer
  checkVkResult vkBindBufferMemory(x.device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc createBuffers(x: var MandelbrotGenerator) =
  # Allocate memory for both buffers
  (x.storageBuffer, x.storageBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(float32)*4*x.width*x.height),
    VkBufferUsageFlags(VkBufferUsageFlagBits.StorageBufferBit),
    VkMemoryPropertyFlags(HostCoherentBit.uint32 or HostCoherentBit.uint32))
  (x.uniformBuffer, x.uniformBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(int32)*2),
    VkBufferUsageFlags(VkBufferUsageFlagBits.UniformBufferBit),
    VkMemoryPropertyFlags(HostCoherentBit.uint32 or HostCoherentBit.uint32))
  # Map the memory and write to the uniform buffer
  var mappedMemory: pointer = nil
  checkVkResult vkMapMemory(x.device, x.uniformBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(int32)*2), 0.VkMemoryMapFlags, mappedMemory.addr)
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
  checkVkResult vkCreateDescriptorSetLayout(x.device, createInfo.addr,
      nil, x.descriptorSetLayout.addr)

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
  checkVkResult vkCreateDescriptorPool(x.device, descriptorPoolCreateInfo.addr, nil, x.descriptorPool.addr)
  # Allocate a descriptor set
  let descriptorSetAllocateInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = x.descriptorPool,
    descriptorSetCount = 1,
    pSetLayouts = x.descriptorSetLayout.addr
  )
  var descriptorSet: VkDescriptorSet
  checkVkResult vkAllocateDescriptorSets(x.device, descriptorSetAllocateInfo.addr, descriptorSet.addr)
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
  vkUpdateDescriptorSets(x.device, writeDescriptorSets.len.uint32, writeDescriptorSets[0].addr, 0, nil)

proc createComputePipeline(x: var MandelbrotGenerator) =
  # Create the shader module
  let computeShaderCode = readFile("build/shaders/mandelbrot.spv")
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    codeSize = computeShaderCode.len.uint,
    pCode = cast[ptr uint32](computeShaderCode[0].addr))
  var computeShaderModule: VkShaderModule
  checkVkResult vkCreateShaderModule(x.device, shaderModuleCreateInfo.addr, nil, computeShaderModule.addr)
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
  checkVkResult vkCreatePipelineLayout(x.device, pipelineLayoutCreateInfo.addr, nil, x.pipelineLayout.addr)
  # Create the compute pipeline
  let computePipelineCreateInfo = newVkComputePipelineCreateInfo(
    stage = shaderStageCreateInfo,
    layout = x.pipelineLayout,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1
  )
  checkVkResult vkCreateComputePipelines(x.device, 0.VkPipelineCache, 1,
      computePipelineCreateInfo.addr, nil, x.pipeline.addr)
  vkDestroyShaderModule(x.device, computeShaderModule, nil)

proc createCommandBuffer(x: var MandelbrotGenerator) =
  # Create a command pool
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = x.queueFamilyIndex
  )
  checkVkResult vkCreateCommandPool(x.device, commandPoolCreateInfo.addr, nil, x.commandPool.addr)
  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = x.commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
    )
  checkVkResult vkAllocateCommandBuffers(x.device, commandBufferAllocateInfo.addr, x.commandBuffer.addr)
  # Begin recording the command buffer
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(VkCommandBufferUsageFlagBits.OneTimeSubmitBit),
    pInheritanceInfo = nil
  )
  checkVkResult vkBeginCommandBuffer(x.commandBuffer, commandBufferBeginInfo.addr)
  # Bind the compute pipeline
  vkCmdBindPipeline(x.commandBuffer, VkPipelineBindPoint.Compute, x.pipeline)
  # Bind the descriptor set
  vkCmdBindDescriptorSets(x.commandBuffer, VkPipelineBindPoint.Compute, x.pipelineLayout,
      0, 1, x.descriptorSets[0].addr, 0, nil)
  # Dispatch the compute work
  let numWorkgroupX = uint32(ceil(float32(x.width) / float32(x.workgroupSize.x)))
  let numWorkgroupY = uint32(ceil(float32(x.height) / float32(x.workgroupSize.y)))
  vkCmdDispatch(x.commandBuffer, numWorkgroupX, numWorkgroupY, 1)
  # End recording the command buffer
  checkVkResult vkEndCommandBuffer(x.commandBuffer)

proc submitCommandBuffer(x: var MandelbrotGenerator) =
  let submitInfo = newVkSubmitInfo(
    waitSemaphoreCount = 0,
    pWaitSemaphores = nil,
    pWaitDstStageMask = nil,
    commandBufferCount = 1,
    pCommandBuffers = x.commandBuffer.addr,
    signalSemaphoreCount = 0,
    pSignalSemaphores = nil
  )
  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo()
  var fence: VkFence
  checkVkResult vkCreateFence(x.device, fenceCreateInfo.addr, nil, fence.addr)
  # Submit the command buffer
  checkVkResult vkQueueSubmit(x.queue, 1, submitInfo.addr, fence)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  checkVkResult vkWaitForFences(x.device, 1, fence.addr, VkBool32(true), high(uint64))
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
    let severityFlags = VkDebugUtilsMessageSeverityFlagsEXT(
      VerboseBit.uint32 or InfoBit.uint32 or
      VkDebugUtilsMessageSeverityFlagBitsEXT.WarningBit.uint32 or
      VkDebugUtilsMessageSeverityFlagBitsEXT.ErrorBit.uint32)
    let messageTypeFlags = VkDebugUtilsMessageTypeFlagsEXT(
      GeneralBit.uint32 or
      VkDebugUtilsMessageTypeFlagBitsEXT.ValidationBit.uint32 or PerformanceBit.uint32)
    let createInfo = newVkDebugUtilsMessengerCreateInfoEXT(
      messageSeverity = severityFlags,
      messageType = messageTypeFlags,
      pfnUserCallback = debugCallback
    )
    checkVkResult vkCreateDebugUtilsMessengerEXT(x.instance, createInfo.addr, nil, x.debugUtilsMessenger.addr)

proc generate*(x: var MandelbrotGenerator): seq[uint8] =
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
