import vulkan, vulkan_wrapper, renderdoc, std/sequtils

when defined(vkDebug):
  proc debugCallback(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
                     messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
                     pCallbackData: ptr VkDebugUtilsMessengerCallbackDataEXT,
                     pUserData: pointer): VkBool32 {.cdecl.} =
    stderr.write(pCallbackData.pMessage)
    return false.VkBool32

  proc setupDebugUtilsMessenger(instance: VkInstance): VkDebugUtilsMessengerEXT =
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

proc main() =
  vkPreload()
  let applicationInfo = newVkApplicationInfo(
    pApplicationName = "Hello World",
    applicationVersion = 0,
    pEngineName = cstring(nil),
    engineVersion = 0,
    apiVersion = vkApiVersion1_3
  )
  when defined(vkDebug):
    # Enable the Khronos validation layer
    let layerProperties = enumerateInstanceLayerProperties()
    let foundValidationLayer = layerProperties.anyIt(
        "VK_LAYER_KHRONOS_validation" == cast[cstring](it.layerName.addr))
    assert foundValidationLayer, "Validation layer required, but not available"
    # Shader printf is a feature of the validation layers that needs to be enabled
    let enables = [VkValidationFeatureEnableEXT.DebugPrintf]
    let features = newVkValidationFeaturesEXT(
      pEnabledValidationFeatures = addr enables[0],
      enabledValidationFeatureCount = uint32(enables.len),
      pDisabledValidationFeatures = nil,
      disabledValidationFeatureCount = 0
    )
  let layers = getLayers()
  let extensions = getExtensions()
  let instanceInfo = newVkInstanceCreateInfo(
    pNext = when defined(vkDebug): addr features else: nil,
    pApplicationInfo = addr applicationInfo,
    enabledLayerCount = layers.len.uint32,
    ppEnabledLayerNames = layers.toCStringArray,
    enabledExtensionCount = extensions.len.uint32,
    ppEnabledExtensionNames = extensions.toCStringArray
  )
  let instance = createInstance(instanceInfo)
  vkInit(instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
    loadVkExtDebugUtils()
    let debugUtilsMessenger = setupDebugUtilsMessenger(instance)
  # when defined(useRenderDoc): rDocInit()
  let physicalDevices = enumeratePhysicalDevices(instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  let physicalDevice = physicalDevices[0]

  var family: uint32 = 0
  var queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0..queueFamilyProperties.high:
    if (queueFamilyProperties[i].queueFlags.uint32 and VkQueueFlagBits.ComputeBit.uint32) != 0:
      family = i.uint32
      break

  let priority: array[1, float32] = [1.0]
  let deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = family,
    queueCount = 1,
    pQueuePriorities = priority[0].addr
  )
  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfoCount = 1,
    pQueueCreateInfos = addr deviceQueueCreateInfo,
    enabledLayerCount = 0,
    ppEnabledLayerNames = nil,
    enabledExtensionCount = 0,
    ppEnabledExtensionNames = nil,
    pEnabledFeatures = nil
  )
  let device = createDevice(physicalDevice, deviceCreateInfo)

  let spirv = readFile("build/shaders/hello_world.comp.spv")
  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    codeSize = spirv.len.uint,
    pCode = cast[ptr uint32](spirv[0].addr)
  )
  let shaderModule = createShaderModule(device, shaderModuleCreateInfo)

  let stageCreateInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = shaderModule,
    pName = "main",
    pSpecializationInfo = nil
  )
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayoutCount = 0,
    pSetLayouts = nil,
    pushConstantRangeCount = 0,
    pPushConstantRanges = nil
  )
  let pipelineLayout = createPipelineLayout(device, pipelineLayoutCreateInfo)

  let pipelineCreateInfos = [
    newVkComputePipelineCreateInfo(
      stage = stageCreateInfo,
      layout = pipelineLayout,
      basePipelineHandle = 0.VkPipeline,
      basePipelineIndex = -1
    )
  ]
  let pipeline = createComputePipelines(device, 0.VkPipelineCache, pipelineCreateInfos)

  let commandPoolCreateInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = family
  )
  let commandPool = createCommandPool(device, commandPoolCreateInfo)

  let allocateInfo = newVkCommandBufferAllocateInfo(
    commandPool = commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1
  )
  let commandBuffer = allocateCommandBuffers(device, allocateInfo)

  let beginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags(OneTimeSubmitBit),
    pInheritanceInfo = nil
  )
  beginCommandBuffer(commandBuffer, beginInfo)
  vkCmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, pipeline)
  vkCmdDispatch(commandBuffer, 8, 1, 1)
  endCommandBuffer(commandBuffer)

  var queue = getDeviceQueue(device, family, 0)
  let submitInfo = newVkSubmitInfo(
    waitSemaphoreCount = 0,
    pWaitSemaphores = nil,
    pWaitDstStageMask = nil,
    commandBufferCount = 1,
    pCommandBuffers = addr commandBuffer,
    signalSemaphoreCount = 0,
    pSignalSemaphores = nil
  )
  # when defined(useRenderDoc): startFrameCapture(instance)
  queueSubmit(queue, [submitInfo], 0.VkFence)
  # when defined(useRenderDoc): endFrameCapture(instance)
  discard vkDeviceWaitIdle(device)

  # Cleanup resources
  vkDestroyCommandPool(device, commandPool, nil)
  vkDestroyPipeline(device, pipeline, nil)
  vkDestroyPipelineLayout(device, pipelineLayout, nil)
  vkDestroyShaderModule(device, shaderModule, nil)
  vkDestroyDevice(device, nil)
  when defined(vkDebug):
    vkDestroyDebugUtilsMessengerEXT(instance, debugUtilsMessenger, nil)
  vkDestroyInstance(instance, nil)

main()
