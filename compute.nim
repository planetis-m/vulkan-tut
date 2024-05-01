import vulkan, std/strutils

template toCString(arr: array): untyped = cast[cstring](addr arr)
template toCStringArray(arr: array): untyped = cast[cstringArray](addr arr)

proc alignUp(value, alignment: VkDeviceSize): VkDeviceSize {.inline.} =
  VkDeviceSize((value.uint64 + alignment.uint64 - 1) and not (alignment.uint64 - 1))

proc main =
  vkPreload()

  # Create an ApplicationInfo struct
  let appInfo = newVkApplicationInfo(
    pApplicationName = "VulkanCompute",
    applicationVersion = 1,
    pEngineName = nil,
    engineVersion = 0,
    apiVersion = vkApiVersion1_1
  )

  # Enable the Khronos validation layer
  let enabledLayerNames = [cstring"VK_LAYER_KHRONOS_validation"]

  # Create a Vulkan instance
  let instanceCreateInfo = newVkInstanceCreateInfo(
    flags = 0.VkInstanceCreateFlags,
    pApplicationInfo = appInfo.addr,
    enabledLayerCount = 1,
    ppEnabledLayerNames = enabledLayerNames.toCStringArray,
    enabledExtensionCount = 0,
    ppEnabledExtensionNames = nil
  )

  var instance: VkInstance
  doAssert vkCreateInstance(instanceCreateInfo.addr, nil, instance.addr) == VkSuccess

  vkInit(instance, load1_2 = false, load1_3 = false)

  # Enumerate physical devices
  var physicalDeviceCount: uint32 = 0
  discard vkEnumeratePhysicalDevices(instance, physicalDeviceCount.addr, nil)

  var physicalDevices = newSeq[VkPhysicalDevice](physicalDeviceCount)
  discard vkEnumeratePhysicalDevices(instance, physicalDeviceCount.addr, physicalDevices[0].addr)

  doAssert physicalDeviceCount != 0

  # Use the first physical device
  let physicalDevice = physicalDevices[0]

  # Get device properties
  var deviceProperties = VkPhysicalDeviceProperties()
  vkGetPhysicalDeviceProperties(physicalDevice, deviceProperties.addr)

  echo "Selected physical device: ", deviceProperties.deviceName.toCString
  echo "API version: ", vkVersionMajor(deviceProperties.apiVersion), ".", vkVersionMinor(deviceProperties.apiVersion), ".", vkVersionPatch(deviceProperties.apiVersion)
  echo "Max compute shared memory size: ", formatSize(deviceProperties.limits.maxComputeSharedMemorySize.int64)

  # Find a compute queue family
  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, nil)

  var queueFamilyProps = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, queueFamilyProps[0].addr)

  var queueIndex = -1
  for i in 0 ..< queueFamilyProps.len:
    let prop = queueFamilyProps[i]
    if (prop.queueFlags.uint32 and VkQueueFlagBits.ComputeBit.uint32) != 0:
      queueIndex = i
      break

  doAssert queueIndex != -1

  var computeQueueFamilyIndex = queueIndex.uint32
  echo "Compute Queue Family Index: ", computeQueueFamilyIndex

  let queuePriority = 1'f32
  let queueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = computeQueueFamilyIndex,
    queueCount = 1,
    pQueuePriorities = queuePriority.addr
  )

  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfoCount = 1,
    pQueueCreateInfos = queueCreateInfo.addr,
    enabledLayerCount = 0,
    ppEnabledLayerNames = nil,
    enabledExtensionCount = 0,
    ppEnabledExtensionNames = nil,
    pEnabledFeatures = nil
  )

  # Create a logical device
  var device: VkDevice
  doAssert vkCreateDevice(physicalDevice, deviceCreateInfo.addr, nil, device.addr) == VkSuccess

  # Create buffers
  const NumElements = 10
  const BufferSize = NumElements*sizeof(int32)

  let bufferCreateInfo = newVkBufferCreateInfo(
    size = BufferSize.VkDeviceSize,
    usage = VkBufferUsageFlags(VkBufferUsageFlagBits.StorageBufferBit),
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndexCount = 1,
    pQueueFamilyIndices = computeQueueFamilyIndex.addr
  )

  var inBuffer, outBuffer: VkBuffer
  doAssert vkCreateBuffer(device, bufferCreateInfo.addr, nil, inBuffer.addr) == VkSuccess
  doAssert vkCreateBuffer(device, bufferCreateInfo.addr, nil, outBuffer.addr) == VkSuccess

  # Memory req
  var inMemRequirements: VkMemoryRequirements
  vkGetBufferMemoryRequirements(device, inBuffer, inMemRequirements.addr)
  var outMemRequirements: VkMemoryRequirements
  vkGetBufferMemoryRequirements(device, inBuffer, outMemRequirements.addr)

  # query
  var memProperties: VkPhysicalDeviceMemoryProperties
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, memProperties.addr)

  var memTypeIndex = -1
  var memHeapSize = 0.VkDeviceSize
  let memFlags = VkMemoryPropertyFlags(HostVisibleBit.uint32 or HostCoherentBit.uint32)

  for i in 0 ..< memProperties.memoryTypeCount.int:
    let memoryType = memProperties.memoryTypes[i]
    if (memoryType.propertyFlags.uint32 and memFlags.uint32) == memFlags.uint32:
      memHeapSize = memProperties.memoryHeaps[memoryType.heapIndex].size
      memTypeIndex = i
      break

  echo "Memory Type Index: ", memTypeIndex
  echo "Memory Heap Size : ", formatSize(memHeapSize.int64)

  # Determine the size and alignment for the combined memory
  let alignedSize = alignUp(inMemRequirements.size, outMemRequirements.alignment)
  let combinedSize = VkDeviceSize(alignedSize.uint64 + outMemRequirements.size.uint64)

  # Allocate memory for both buffers
  var memAllocateInfo = newVkMemoryAllocateInfo(
    allocationSize = combinedSize,
    memoryTypeIndex = memTypeIndex.uint32
  )

  var bufferMemory: VkDeviceMemory
  doAssert vkAllocateMemory(device, memAllocateInfo.addr, nil, bufferMemory.addr) == VkSuccess

  # Map the memory and write to the input buffer
  var inBufferPtr: ptr array[NumElements, int32] = nil
  doAssert vkMapMemory(device, bufferMemory, 0.VkDeviceSize, BufferSize.VkDeviceSize,
      0.VkMemoryMapFlags, cast[ptr pointer](inBufferPtr.addr)) == VkSuccess

  for i in 0 ..< NumElements:
    inBufferPtr[i] = int32(i)

  vkUnmapMemory(device, bufferMemory)

  # Bind the memory to the input buffer
  doAssert vkBindBufferMemory(device, inBuffer, bufferMemory, 0.VkDeviceSize) == VkSuccess

  # Bind the memory to the output buffer at the aligned offset
  doAssert vkBindBufferMemory(device, outBuffer, bufferMemory, alignedSize) == VkSuccess

  let shaderCode = readFile("shaders/shader.spv")
  # Create a VkShaderModuleCreateInfo struct
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    codeSize = shaderCode.len.uint,
    pCode = cast[ptr uint32](shaderCode[0].addr)
  )

  # Create the shader module
  var shaderModule: VkShaderModule
  doAssert vkCreateShaderModule(device, shaderModuleCreateInfo.addr, nil, shaderModule.addr) == VkSuccess

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
    bindingCount = descriptorSetLayoutBindings.len.uint32,
    pBindings = descriptorSetLayoutBindings[0].addr
  )

  var descriptorSetLayout: VkDescriptorSetLayout
  doAssert vkCreateDescriptorSetLayout(device, descriptorSetLayoutCreateInfo.addr, nil, descriptorSetLayout.addr) == VkSuccess

  # Create a pipeline layout with the descriptor set layout
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayoutCount = 1,
    pSetLayouts = descriptorSetLayout.addr,
    pushConstantRangeCount = 0,
    pPushConstantRanges = nil
  )

  var pipelineLayout: VkPipelineLayout
  doAssert vkCreatePipelineLayout(device, pipelineLayoutCreateInfo.addr, nil, pipelineLayout.addr) == VkSuccess

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

  var computePipeline: VkPipeline
  doAssert vkCreateComputePipelines(device, 0.VkPipelineCache, 1, pipelineCreateInfo.addr, nil, computePipeline.addr) == VkSuccess

  # Create a descriptor pool
  let poolSize = newVkDescriptorPoolSize(
    `type` = VkDescriptorType.StorageBuffer,
    descriptorCount = 2 # One for the input buffer and one for the output buffer
  )

  let descriptorPoolCreateInfo = newVkDescriptorPoolCreateInfo(
    maxSets = 1, # We only need one set
    poolSizeCount = 1,
    pPoolSizes = poolSize.addr
  )

  var descriptorPool: VkDescriptorPool
  doAssert vkCreateDescriptorPool(device, descriptorPoolCreateInfo.addr, nil, descriptorPool.addr) == VkSuccess

  # Allocate a descriptor set
  let allocInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = descriptorPool,
    descriptorSetCount = 1,
    pSetLayouts = descriptorSetLayout.addr
  )

  var descriptorSet: VkDescriptorSet
  doAssert vkAllocateDescriptorSets(device, allocInfo.addr, descriptorSet.addr) == VkSuccess

  # Update the descriptor set with the buffer information
  let descriptorBufferInfo = [
    newVkDescriptorBufferInfo(
      buffer = inBuffer,
      offset = 0.VkDeviceSize,
      range = BufferSize.VkDeviceSize
    ),
    newVkDescriptorBufferInfo(
      buffer = outBuffer,
      offset = 0.VkDeviceSize,
      range = BufferSize.VkDeviceSize
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

  vkUpdateDescriptorSets(device, writeDescriptorSet.len.uint32, writeDescriptorSet[0].addr, 0, nil)

  # Create a command pool
  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    flags = VkCommandPoolCreateFlags(VkCommandPoolCreateFlagBits.ResetCommandBufferBit),
    queueFamilyIndex = computeQueueFamilyIndex
  )

  var commandPool: VkCommandPool
  doAssert vkCreateCommandPool(device, commandPoolCreateInfo.addr, nil, commandPool.addr) == VkSuccess

  # Allocate a command buffer from the command pool
  let commandBufferAllocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )

  var commandBuffer: VkCommandBuffer
  doAssert vkAllocateCommandBuffers(device, commandBufferAllocateInfo.addr, commandBuffer.addr) == VkSuccess

  # Begin recording the command buffer
  let commandBufferBeginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(VkCommandBufferUsageFlagBits.OneTimeSubmitBit),
    pInheritanceInfo = nil
  )

  doAssert vkBeginCommandBuffer(commandBuffer, commandBufferBeginInfo.addr) == VkSuccess

  # Bind the compute pipeline
  vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, computePipeline)

  # Bind the descriptor set
  vkCmdBindDescriptorSets(commandBuffer, VkPipelineBindPoint.Compute, pipelineLayout,
      0, 1, descriptorSet.addr, 0, nil)

  # Dispatch the compute work
  # const WorkGroupSize = 32 # This should match your shader's local workgroup size
  # let numGroupsX = (NumElements + WorkGroupSize - 1) div WorkGroupSize
  vkCmdDispatch(commandBuffer, NumElements, 1, 1)

  # End recording the command buffer
  doAssert vkEndCommandBuffer(commandBuffer) == VkSuccess

  # Submit the command buffer to the queue
  let submitInfo = newVkSubmitInfo(
    waitSemaphoreCount = 0,
    pWaitSemaphores = nil,
    pWaitDstStageMask = nil,
    commandBufferCount = 1,
    pCommandBuffers = commandBuffer.addr,
    signalSemaphoreCount = 0,
    pSignalSemaphores = nil
  )

  # Get the compute queue
  var computeQueue: VkQueue
  vkGetDeviceQueue(device, computeQueueFamilyIndex, 0, computeQueue.addr)

  # Create a fence
  let fenceCreateInfo = newVkFenceCreateInfo(
    flags = 0.VkFenceCreateFlags # Initially unsignaled
  )

  var fence: VkFence
  doAssert vkCreateFence(device, fenceCreateInfo.addr, nil, fence.addr) == VkSuccess

  # Submit the command buffer
  doAssert vkQueueSubmit(computeQueue, 1, submitInfo.addr, fence) == VkSuccess

  # Wait for the fence to be signaled, indicating completion of the command buffer execution
  doAssert vkWaitForFences(device, 1, fence.addr, true.VkBool32, high(uint64)) == VkSuccess

  # Map the output buffer to read the results
  var outBufferPtr: ptr array[NumElements, int32] = nil
  doAssert vkMapMemory(device, bufferMemory, alignedSize, BufferSize.VkDeviceSize,
      0.VkMemoryMapFlags, cast[ptr pointer](outBufferPtr.addr)) == VkSuccess

  echo "OUTPUT: ", outBufferPtr[]

  vkUnmapMemory(device, bufferMemory)

  # Clean up
  vkDestroyFence(device, fence, nil)
  vkDestroyCommandPool(device, commandPool, nil)
  vkDestroyDescriptorPool(device, descriptorPool, nil)
  vkDestroyPipeline(device, computePipeline, nil)
  vkDestroyPipelineLayout(device, pipelineLayout, nil)
  vkDestroyDescriptorSetLayout(device, descriptorSetLayout, nil)
  vkDestroyShaderModule(device, shaderModule, nil)
  vkFreeMemory(device, bufferMemory, nil)
  vkDestroyBuffer(device, inBuffer, nil)
  vkDestroyBuffer(device, outBuffer, nil)
  vkDestroyDevice(device, nil)
  vkDestroyInstance(instance, nil)

main()
