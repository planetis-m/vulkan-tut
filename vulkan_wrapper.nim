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

proc unmapMemory*(device: VkDevice, memory: VkDeviceMemory) =
  vkUnmapMemory(device, memory)

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
  assert layerCount.int <= result.len
  if layerCount.int < result.len:
    result.setLen(layerCount)

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
  assert physicalDeviceCount.int <= result.len
  if physicalDeviceCount.int < result.len:
    result.setLen(physicalDeviceCount)
