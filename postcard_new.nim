import vulkan, vulkan_wrapper, vulkan_functions, renderdoc, std/sequtils

proc main() =
  let layers = getLayers()
  let extensions = getExtensions()
  vkPreload()
  let instance = createInstance("Hello World", nil, layers, extensions)
  vkInit(instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
    loadVkExtDebugUtils()
    let debugUtilsMessenger = setupDebugUtilsMessenger(instance)
  when defined(useRenderDoc):
    rDocInit()

  let physicalDevice = findPhysicalDevice(instance)
  let queueFamilyIndex = getComputeQueueFamilyIndex(physicalDevice)
  let device = createDevice(physicalDevice, queueFamilyIndex, layers, [], [])
  let queue = getDeviceQueue(device, queueFamilyIndex, 0)

  let shaderPath = "build/shaders/hello_world.comp.spv"
  let shaderModule = createShaderModule(device, readFile(shaderPath))
  let pipelineLayoutCreateInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [],
    pushConstantRanges = []
  )
  let pipelineLayout = createPipelineLayout(device, pipelineLayoutCreateInfo)
  let pipeline = createComputePipeline(device, shaderModule, pipelineLayout, specializationEntries = [], nil, 0)
  # Create command pool
  let commandPool = createCommandPool(device, queueFamilyIndex)

  # Allocate command buffer
  let commandBuffer = allocateCommandBuffer(device, commandPool)

  # Record command buffer
  recordCommandBuffer(commandBuffer, pipeline, pipelineLayout, descriptorSets = [])
  # Submit command buffer
  submitCommandBuffer(device, queue, commandBuffer, instance)

  # Cleanup resources
  destroyCommandPool(device, commandPool)
  destroyPipeline(device, pipeline)
  destroyPipelineLayout(device, pipelineLayout)
  destroyDevice(device)
  when defined(vkDebug):
    destroyDebugUtilsMessenger(instance, debugUtilsMessenger)
  destroyInstance(instance)

main()
