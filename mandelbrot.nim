# https://youtu.be/1BMGTyIF5dI
import vulkan, std/[sequtils, math]

type
  MandelbrotGenerator* = object
    width*, height*: int32
    workgroupSize*: WorkgroupSize
    instance*: VkInstance
    physicalDevice*: VkPhysicalDevice
    device*: VkDevice
    queue*: VkQueue
    queueFamilyIndex*: uint32
    storageBuffer*: VkBuffer
    storageBufferMemory*: VkDeviceMemory
    uniformBuffer*: VkBuffer
    uniformBufferMemory*: VkDeviceMemory
    descriptorSetLayout*: VkDescriptorSetLayout
    descriptorPool*: VkDescriptorPool
    descriptorSets*: seq[VkDescriptorSet]
    pipelineLayout*: VkPipelineLayout
    pipeline*: VkPipeline
    commandPool*: VkCommandPool
    commandBuffer*: VkCommandBuffer
    when defined(vkDebug):
      debugUtilsMessenger*: VkDebugUtilsMessengerEXT

  WorkgroupSize* = object
    x*, y*: uint32

template checkVkResult(call: untyped) =
  when defined(danger):
    discard call
  else:
    assert call == VkSuccess

proc `=destroy`*(x: MandelbrotGenerator) =
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
    workgroupSize: WorkgroupSize(x: 8, y: 8)
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

proc createInstance(x: var MandelbrotGenerator) =
  # Create an ApplicationInfo struct
  let applicationInfo = VkApplicationInfo(
    pApplicationName: "Mandelbrot",
    applicationVersion: vkMakeVersion(0, 1, 0, 0),
    pEngineName: "No Engine",
    engineVersion: vkMakeVersion(0, 1, 0, 0),
    apiVersion: vkApiVersion1_1
  )
  when defined(vkDebug):
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
  let instanceCreateInfo = VkInstanceCreateInfo(
    pApplicationInfo: applicationInfo.addr,
    enabledLayerCount: uint32(layers.len),
    ppEnabledLayerNames: if layers.len == 0: nil else: cast[cstringArray](layers[0].addr),
    enabledExtensionCount: uint32(extensions.len),
    ppEnabledExtensionNames: if extensions.len == 0: nil else: cast[cstringArray](extensions[0].addr)
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
  let queueCreateInfo = VkDeviceQueueCreateInfo(
    queueFamilyIndex: x.queueFamilyIndex,
    queueCount: 1,
    pQueuePriorities: queuePriority.addr
  )
  let layers = getLayers()
  let physicalDeviceFeatures = VkPhysicalDeviceFeatures()
  let deviceCreateInfo = VkDeviceCreateInfo(
    queueCreateInfoCount: 1,
    pQueueCreateInfos: queueCreateInfo.addr,
    enabledLayerCount: uint32(layers.len),
    ppEnabledLayerNames: if layers.len == 0: nil else: cast[cstringArray](layers[0].addr),
    pEnabledFeatures: physicalDeviceFeatures.addr
  )
  # Create a logical device
  checkVkResult vkCreateDevice(x.physicalDevice, deviceCreateInfo.addr, nil, x.device.addr)
  # Get the compute queue
  vkGetDeviceQueue(x.device, x.queueFamilyIndex, 0, x.queue.addr)

proc findMemoryType(physicalDevice: VkPhysicalDevice, typeFilter: uint32,
    properties: VkMemoryPropertyFlags): uint32 =
  # Find a suitable memory type for a Vulkan physical device
  var memoryProperties: VkPhysicalDeviceMemoryProperties
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, memoryProperties.addr)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    if (typeFilter and (1'u32 shl i.uint32)) != 0 and
       (memoryProperties.memoryTypes[i].propertyFlags.uint32 and properties.uint32) == properties.uint32:
      return i.uint32
  assert false, "Failed to find suitable memory type"

proc createBuffer(x: MandelbrotGenerator, size: VkDeviceSize, usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferCreateInfo = VkBufferCreateInfo(
    size: size,
    usage: usage,
    sharingMode: VkSharingMode.Exclusive
  )
  var buffer: VkBuffer
  checkVkResult vkCreateBuffer(x.device, bufferCreateInfo.addr, nil, buffer.addr)
  var bufferMemoryRequirements: VkMemoryRequirements
  vkGetBufferMemoryRequirements(x.device, buffer, bufferMemoryRequirements.addr)
  # Allocate memory for the buffer
  let allocInfo = VkMemoryAllocateInfo(
    allocationSize: bufferMemoryRequirements.size,
    memoryTypeIndex: findMemoryType(x.physicalDevice, bufferMemoryRequirements.memoryTypeBits, properties)
  )
  var bufferMemory: VkDeviceMemory
  checkVkResult vkAllocateMemory(x.device, allocInfo.addr, nil, bufferMemory.addr)
  # Bind the memory to the buffer
  checkVkResult vkBindBufferMemory(x.device, buffer, bufferMemory, 0.VkDeviceSize)
  result = (buffer, bufferMemory)

proc createBuffers(x: var MandelbrotGenerator) =
  (x.storageBuffer, x.storageBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(float32)*4*x.width*x.height),
    VkBufferUsageFlags(StorageBufferBit),
    VkMemoryPropertyFlags(HostCoherentBit.uint32 or HostCoherentBit.uint32)
  )
  (x.uniformBuffer, x.uniformBufferMemory) = x.createBuffer(
    VkDeviceSize(sizeof(int32)*2),
    VkBufferUsageFlags(UniformBufferBit),
    VkMemoryPropertyFlags(HostCoherentBit.uint32 or HostCoherentBit.uint32)
  )
  var mappedMemory: pointer = nil
  checkVkResult vkMapMemory(x.device, x.uniformBufferMemory, 0.VkDeviceSize,
      VkDeviceSize(sizeof(int32)*2), 0.VkMemoryMapFlags, mappedMemory.addr)
  let ubo = [x.width.int32, x.height.int32]
  copyMem(mappedMemory, ubo.addr, sizeof(int32)*2)
  vkUnmapMemory(x.device, x.uniformBufferMemory)

proc createDescriptorSetLayout(x: var MandelbrotGenerator) =
  let bindings = [
    VkDescriptorSetLayoutBinding(
      binding: 0,
      descriptorType: VkDescriptorType.StorageBuffer,
      descriptorCount: 1,
      stageFlags: VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit)
    ),
    VkDescriptorSetLayoutBinding(
      binding: 1,
      descriptorType: VkDescriptorType.UniformBuffer,
      descriptorCount: 1,
      stageFlags: VkShaderStageFlags(VkShaderStageFlagBits.ComputeBit)
    )
  ]
  let createInfo = VkDescriptorSetLayoutCreateInfo(
    bindingCount: bindings.len.uint32,
    pBindings: bindings[0].addr
  )
  checkVkResult vkCreateDescriptorSetLayout(x.device, createInfo.addr,
      nil, x.descriptorSetLayout.addr)

proc createDescriptorSets(x: var MandelbrotGenerator) =
  let descriptorPoolSizes = [
    VkDescriptorPoolSize(
      `type`: VkDescriptorType.StorageBuffer,
      descriptorCount: 1),
    VkDescriptorPoolSize(
      `type`: VkDescriptorType.UniformBuffer,
      descriptorCount: 1)
  ]
  let descriptorPoolCreateInfo = VkDescriptorPoolCreateInfo(
    maxSets: 2,
    poolSizeCount: descriptorPoolSizes.len.uint32,
    pPoolSizes: descriptorPoolSizes[0].addr
  )
  checkVkResult vkCreateDescriptorPool(x.device, descriptorPoolCreateInfo.addr, nil, x.descriptorPool.addr)
  let descriptorSetAllocateInfo = VkDescriptorSetAllocateInfo(
    descriptorPool: x.descriptorPool,
    descriptorSetCount: 1,
    pSetLayouts: x.descriptorSetLayout.addr
  )
  var descriptorSet: VkDescriptorSet
  checkVkResult vkAllocateDescriptorSets(x.device, descriptorSetAllocateInfo.addr, descriptorSet.addr)
  x.descriptorSets = @[descriptorSet]
  let descriptorStorageBufferInfo = VkDescriptorBufferInfo(
    buffer: x.storageBuffer,
    offset: 0.VkDeviceSize,
    range: VkDeviceSize(sizeof(float32)*4*x.width*x.height)
  )
  let descriptorUniformBufferInfo = VkDescriptorBufferInfo(
    buffer: x.uniformBuffer,
    offset: 0.VkDeviceSize,
    range: VkDeviceSize(sizeof(int32)*2)
  )
  let writeDescriptorSets = [
    VkWriteDescriptorSet(
      dstSet: x.descriptorSets[0],
      dstBinding: 0,
      descriptorCount: 1,
      descriptorType: VkDescriptorType.StorageBuffer,
      pBufferInfo: descriptorStorageBufferInfo.addr
    ),
    VkWriteDescriptorSet(
      dstSet: x.descriptorSets[0],
      dstBinding: 1,
      descriptorCount: 1,
      descriptorType: VkDescriptorType.UniformBuffer,
      pBufferInfo: descriptorUniformBufferInfo.addr
    )
  ]
  vkUpdateDescriptorSets(x.device, writeDescriptorSets.len.uint32, writeDescriptorSets[0].addr, 0, nil)

proc createComputePipeline(x: var MandelbrotGenerator) =
  let computeShaderCode = readFile("build/shaders/mandelbrot.spv")
  let shaderModuleCreateInfo = VkShaderModuleCreateInfo(
    codeSize: computeShaderCode.len.uint,
    pCode: cast[ptr uint32](computeShaderCode[0].addr)
  )
  var computeShaderModule: VkShaderModule
  checkVkResult vkCreateShaderModule(x.device, shaderModuleCreateInfo.addr, nil, computeShaderModule.addr)
  let specializationMapEntries = [
    VkSpecializationMapEntry(
      constantID: 0,
      offset: offsetOf(WorkgroupSize, x).uint32,
      size: sizeof(uint32).uint
    ),
    VkSpecializationMapEntry(
      constantID: 1,
      offset: offsetOf(WorkgroupSize, y).uint32,
      size: sizeof(uint32).uint
    )
  ]
  let specializationInfo = VkSpecializationInfo(
    mapEntryCount: specializationMapEntries.len.uint32,
    pMapEntries: specializationMapEntries[0].addr,
    dataSize: sizeof(WorkgroupSize).uint,
    pData: x.workgroupSize.addr
  )
  let shaderStageCreateInfo = VkPipelineShaderStageCreateInfo(
    stage: VkShaderStageFlagBits.ComputeBit,
    module: computeShaderModule,
    pName: "main",
    pSpecializationInfo: specializationInfo.addr
  )
  let pipelineLayoutCreateInfo = VkPipelineLayoutCreateInfo(
    setLayoutCount: 1,
    pSetLayouts: x.descriptorSetLayout.addr
  )
  checkVkResult vkCreatePipelineLayout(x.device, pipelineLayoutCreateInfo.addr, nil, x.pipelineLayout.addr)
  let computePipelineCreateInfo = VkComputePipelineCreateInfo(
    stage: shaderStageCreateInfo,
    layout: x.pipelineLayout
  )
  checkVkResult vkCreateComputePipelines(x.device, 0.VkPipelineCache, 1,
      computePipelineCreateInfo.addr, nil, x.pipeline.addr)
  vkDestroyShaderModule(x.device, computeShaderModule, nil)

proc createCommandBuffer(x: var MandelbrotGenerator) =
  # Create a command pool
  let commandPoolCreateInfo = VkCommandPoolCreateInfo(
    queueFamilyIndex: x.queueFamilyIndex
  )
  checkVkResult vkCreateCommandPool(x.device, commandPoolCreateInfo.addr, nil, x.commandPool.addr)
  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = VkCommandBufferAllocateInfo(
    commandPool: x.commandPool,
    level: VkCommandBufferLevel.Primary,
    commandBufferCount: 1
  )
  checkVkResult vkAllocateCommandBuffers(x.device, commandBufferAllocateInfo.addr, x.commandBuffer.addr)
  # Begin recording the command buffer
  let commandBufferBeginInfo = VkCommandBufferBeginInfo(
    flags: VkCommandBufferUsageFlags(VkCommandBufferUsageFlagBits.OneTimeSubmitBit)
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
  let submitInfo = VkSubmitInfo(
    commandBufferCount: 1,
    pCommandBuffers: x.commandBuffer.addr
  )
  # Create a fence
  let fenceCreateInfo = VkFenceCreateInfo()
  var fence: VkFence
  checkVkResult vkCreateFence(x.device, fenceCreateInfo.addr, nil, fence.addr)
  # Submit the command buffer
  checkVkResult vkQueueSubmit(x.queue, 1, submitInfo.addr, fence)
  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  checkVkResult vkWaitForFences(x.device, 1, fence.addr, true.VkBool32, high(uint64))
  vkDestroyFence(x.device, fence, nil)

when defined(vkDebug):
  proc setupDebugUtilsMessenger(x: var MandelbrotGenerator) =
    let severityFlags = VkDebugUtilsMessageSeverityFlagBitsEXT(
      VerboseBit.uint32 or InfoBit.uint32 or WarningBit.uint32 or ErrorBit.uint32
    )
    let messageTypeFlags = VkDebugUtilsMessageTypeFlagBitsEXT(
      GeneralBit.uint32 or ValidationBit.uint32 or PerformanceBit.uint32
    )
    let createInfo = VkDebugUtilsMessengerCreateInfoEXT(
      messageSeverity: severityFlags,
      messageType: messageTypeFlags,
      pfnUserCallback: debugCallback
    )
    checkVkResult vkCreateDebugUtilsMessengerEXT(x.instance, createInfo, nil, x.debugUtilsMessenger)

  proc debugCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                    messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                    pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT,
                    pUserData: pointer): VkBool32 {.cdecl.} =
    stderr.write(pCallbackData.pMessage)
    stderr.write("\n")
    return VkFalse

proc generate*(x: var MandelbrotGenerator): seq[uint8] =
  ## Return the raw data of a mandelbrot image.
  vkPreload()
  # Hardware Setup Stage
  createInstance(x)
  vkInit(x.instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
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
