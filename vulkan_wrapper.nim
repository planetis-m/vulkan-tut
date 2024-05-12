import vulkan

type
  VulkanError* = object of CatchableError
    res*: VkResult

proc raiseVkError*(msg: string; res: VkResult) {.noinline, noreturn.} =
  raise (ref VulkanError)(msg: msg, res: res)

template checkVkResult*(call: untyped) =
  when defined(danger):
    discard call
  else:
    let res = call
    if res != VkSuccess:
      raiseVkError(astToStr(call) & " returned " & $res, res)

proc mapMemory*(device: VkDevice, memory: VkDeviceMemory, offset, size: VkDeviceSize, flags: VkMemoryMapFlags): pointer =
  result = nil
  checkVkResult vkMapMemory(device, memory, offset, size, flags, result.addr)

proc enumerateInstanceLayerProperties*: seq[VkLayerProperties] =
  result = @[]
  var layerCount: uint32 = 0
  var res = VkIncomplete
  while res == VkIncomplete:
    res = vkEnumerateInstanceLayerProperties(layerCount.addr, nil)
    if res == VkSuccess and layerCount > 0:
      result.setLen(layerCount)
      res = vkEnumerateInstanceLayerProperties(layerCount.addr, result[0].addr)
  checkVkResult res

proc createInstance*(instanceCreateInfo: VkInstanceCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkInstance =
  checkVkResult vkCreateInstance(instanceCreateInfo.addr, allocator, result.addr)

proc enumeratePhysicalDevices*(instance: VkInstance): seq[VkPhysicalDevice] =
  result = @[]
  var physicalDeviceCount: uint32 = 0
  var res = VkIncomplete
  while res == VkIncomplete:
    res = vkEnumeratePhysicalDevices(instance, physicalDeviceCount.addr, nil)
    if res == VkSuccess and physicalDeviceCount > 0:
      result.setLen(physicalDeviceCount)
      res = vkEnumeratePhysicalDevices(instance, physicalDeviceCount.addr, result[0].addr)
  checkVkResult res

proc getQueueFamilyProperties*(physicalDevice: VkPhysicalDevice): seq[VkQueueFamilyProperties] =
  result = @[]
  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, nil)
  result.setLen(queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, queueFamilyCount.addr, result[0].addr)

proc getMemoryProperties*(physicalDevice: VkPhysicalDevice): VkPhysicalDeviceMemoryProperties =
  vkGetPhysicalDeviceMemoryProperties(physicalDevice, result.addr)

proc createDevice*(physicalDevice: VkPhysicalDevice, deviceCreateInfo: VkDeviceCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkDevice =
  checkVkResult vkCreateDevice(physicalDevice, deviceCreateInfo.addr, allocator, result.addr)

proc getDeviceQueue*(device: VkDevice, queueFamilyIndex: uint32, queueIndex: uint32): VkQueue =
  vkGetDeviceQueue(device, queueFamilyIndex, queueIndex, result.addr)

proc createBuffer*(device: VkDevice, bufferCreateInfo: VkBufferCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkBuffer =
  checkVkResult vkCreateBuffer(device, bufferCreateInfo.addr, allocator, result.addr)

proc getBufferMemoryRequirements*(device: VkDevice, buffer: VkBuffer): VkMemoryRequirements =
  vkGetBufferMemoryRequirements(device, buffer, result.addr)

proc allocateMemory*(device: VkDevice, allocateInfo: VkMemoryAllocateInfo, allocator: ptr VkAllocationCallbacks = nil): VkDeviceMemory =
  checkVkResult vkAllocateMemory(device, allocateInfo.addr, allocator, result.addr)

proc bindBufferMemory*(device: VkDevice, buffer: VkBuffer, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) =
  checkVkResult vkBindBufferMemory(device, buffer, memory, memoryOffset)

proc createDescriptorSetLayout*(device: VkDevice, createInfo: VkDescriptorSetLayoutCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkDescriptorSetLayout =
  checkVkResult vkCreateDescriptorSetLayout(device, createInfo.addr, allocator, result.addr)

proc createDescriptorPool*(device: VkDevice, createInfo: VkDescriptorPoolCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkDescriptorPool =
  checkVkResult vkCreateDescriptorPool(device, createInfo.addr, allocator, result.addr)

proc allocateDescriptorSets*(device: VkDevice, allocateInfo: VkDescriptorSetAllocateInfo): VkDescriptorSet =
  var descriptorSet: VkDescriptorSet
  checkVkResult vkAllocateDescriptorSets(device, allocateInfo.addr, descriptorSet.addr)
  result = descriptorSet

proc updateDescriptorSets*(device: VkDevice, descriptorWrites: openarray[VkWriteDescriptorSet], descriptorCopies: openarray[VkCopyDescriptorSet]) =
  vkUpdateDescriptorSets(device, descriptorWrites.len.uint32, if descriptorWrites.len == 0: nil else: cast[ptr VkWriteDescriptorSet](descriptorWrites), descriptorCopies.len.uint32, if descriptorWrites.len == 0: nil else: cast[ptr VkCopyDescriptorSet](descriptorCopies))

proc createShaderModule*(device: VkDevice, createInfo: VkShaderModuleCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkShaderModule =
  checkVkResult vkCreateShaderModule(device, createInfo.addr, allocator, result.addr)

proc createPipelineLayout*(device: VkDevice, createInfo: VkPipelineLayoutCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkPipelineLayout =
  checkVkResult vkCreatePipelineLayout(device, createInfo.addr, allocator, result.addr)

proc createComputePipelines*(device: VkDevice, pipelineCache: VkPipelineCache, createInfos: openarray[VkComputePipelineCreateInfo], allocator: ptr VkAllocationCallbacks = nil): VkPipeline =
  checkVkResult vkCreateComputePipelines(device, pipelineCache, createInfos.len.uint32, if createInfos.len == 0: nil else: cast[ptr VkComputePipelineCreateInfo](createInfos), allocator, result.addr)

proc createFence*(device: VkDevice, createInfo: VkFenceCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkFence =
  checkVkResult vkCreateFence(device, createInfo.addr, allocator, result.addr)

proc queueSubmit*(queue: VkQueue, submits: openarray[VkSubmitInfo], fence: VkFence) =
  checkVkResult vkQueueSubmit(queue, submits.len.uint32, if submits.len == 0: nil else: cast[ptr VkSubmitInfo](submits), fence)

proc waitForFences*(device: VkDevice, fences: openarray[VkFence], waitAll: VkBool32, timeout: uint64) =
  checkVkResult vkWaitForFences(device, fences.len.uint32, if fences.len == 0: nil else: cast[ptr VkFence](fences), waitAll, timeout)

proc waitForFence*(device: VkDevice, fence: VkFence, waitAll: VkBool32, timeout: uint64) =
  checkVkResult vkWaitForFences(device, 1, fence.addr, waitAll, timeout)

proc createDebugUtilsMessengerEXT*(instance: VkInstance, createInfo: VkDebugUtilsMessengerCreateInfoEXT, allocator: ptr VkAllocationCallbacks = nil): VkDebugUtilsMessengerEXT =
  checkVkResult vkCreateDebugUtilsMessengerEXT(instance, createInfo.addr, allocator, result.addr)

proc createCommandPool*(device: VkDevice, createInfo: VkCommandPoolCreateInfo, allocator: ptr VkAllocationCallbacks = nil): VkCommandPool =
  checkVkResult vkCreateCommandPool(device, createInfo.addr, allocator, result.addr)

proc allocateCommandBuffers*(device: VkDevice, allocateInfo: VkCommandBufferAllocateInfo): VkCommandBuffer =
  checkVkResult vkAllocateCommandBuffers(device, allocateInfo.addr, result.addr)

proc beginCommandBuffer*(commandBuffer: VkCommandBuffer, beginInfo: VkCommandBufferBeginInfo) =
  checkVkResult vkBeginCommandBuffer(commandBuffer, beginInfo.addr)

proc cmdBindDescriptorSets*(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, firstSet: uint32, descriptorSets: openarray[VkDescriptorSet], dynamicOffsets: openarray[uint32]) =
  vkCmdBindDescriptorSets(commandBuffer, pipelineBindPoint, layout, firstSet, descriptorSets.len.uint32, if descriptorSets.len == 0: nil else: cast[ptr VkDescriptorSet](descriptorSets), dynamicOffsets.len.uint32, if dynamicOffsets.len == 0: nil else: cast[ptr uint32](dynamicOffsets))
