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
    createDebugUtilsMessengerEXT(instance, createInfo)

proc getLayers(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add("VK_LAYER_KHRONOS_validation")

proc getExtensions(): seq[cstring] =
  result = @[]
  when defined(vkDebug):
    result.add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)

proc main() =
  vkPreload()
  let applicationInfo = newVkApplicationInfo(
    pApplicationName = "Hello World",
    applicationVersion = 0,
    pEngineName = nil,
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
    let features = newVkValidationFeaturesEXT(
      enabledValidationFeatures = [VkValidationFeatureEnableEXT.DebugPrintf],
      disabledValidationFeatures = []
    )
  let layers = getLayers()
  let extensions = getExtensions()
  let instanceInfo = newVkInstanceCreateInfo(
    pNext = when defined(vkDebug): addr features else: nil,
    pApplicationInfo = addr applicationInfo,
    pEnabledLayerNames = layers,
    pEnabledExtensionNames = extensions
  )
  let instance = createInstance(instanceInfo)
  vkInit(instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
    loadVkExtDebugUtils()
    let debugUtilsMessenger = setupDebugUtilsMessenger(instance)
  when defined(useRenderDoc): rDocInit()
  let physicalDevices = enumeratePhysicalDevices(instance)
  assert physicalDevices.len > 0, "Cannot find any physical devices."
  let physicalDevice = physicalDevices[0]

  var family: uint32 = 0
  var queueFamilyProperties = getQueueFamilyProperties(physicalDevice)
  for i in 0..queueFamilyProperties.high:
    if VkQueueFlagBits.ComputeBit in queueFamilyProperties[i].queueFlags:
      family = i.uint32
      break

  let priority: array[1, float32] = [1.0]
  let deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = family,
    queuePriorities = priority
  )
  let deviceCreateInfo = newVkDeviceCreateInfo(
    queueCreateInfos = [deviceQueueCreateInfo],
    pEnabledLayerNames = [],
    pEnabledExtensionNames = [],
    enabledFeatures = []
  )
  let device = createDevice(physicalDevice, deviceCreateInfo)

  let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
    code = readFile("build/shaders/hello_world.comp.spv")
  )
  let shaderModule = createShaderModule(device, shaderModuleCreateInfo)

  let stageCreateInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = shaderModule,
    pName = "main",
    pSpecializationInfo = nil
  )
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [],
    pushConstantRanges = []
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
  cmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, pipeline)
  cmdDispatch(commandBuffer, 8, 1, 1)
  endCommandBuffer(commandBuffer)

  var queue = getDeviceQueue(device, family, 0)
  let submitInfo = newVkSubmitInfo(
    waitSemaphores = [],
    waitDstStageMask = [],
    commandBuffers = [commandBuffer],
    signalSemaphores = []
  )
  when defined(useRenderDoc): startFrameCapture(instance)
  queueSubmit(queue, [submitInfo], 0.VkFence)
  when defined(useRenderDoc): endFrameCapture(instance)
  deviceWaitIdle(device)

  # Cleanup resources
  destroyCommandPool(device, commandPool)
  destroyPipeline(device, pipeline)
  destroyPipelineLayout(device, pipelineLayout)
  destroyShaderModule(device, shaderModule)
  destroyDevice(device)
  when defined(vkDebug):
    destroyDebugUtilsMessenger(instance, debugUtilsMessenger)
  destroyInstance(instance)

main()
