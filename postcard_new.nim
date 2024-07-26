import
  vulkan, vulkan_wrapper, vulkan_functions, vulkan_shaderc,
  renderdoc, std/sequtils

proc main() =
  let layers = getLayers()
  let extensions = getExtensions()
  vkPreload()
  let instance = createInstance("Hello World", nil, layers, extensions)
  vkInit(instance, load1_2 = false, load1_3 = false)
  when defined(vkDebug):
    loadVkExtDebugUtils()
    let debugUtilsMessenger = setupDebugUtilsMessenger(instance)

  let physicalDevice = findPhysicalDevice(instance)
  let queueFamilyIndex = getComputeQueueFamilyIndex(physicalDevice)
  let device = createDevice(physicalDevice, queueFamilyIndex, layers, [], [])
  let queue = getDeviceQueue(device, queueFamilyIndex, 0)

  let shaderSource = readFile("shaders/hello_world.comp.glsl")
  let shaderModule = createShaderModule(device, shaderSource, ComputeShader, "hello_world.comp")
  let pipelineLayout = createPipelineLayout(device, descriptorSetLayouts = [])
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
  destroyShaderModule(device, shaderModule)
  destroyDevice(device)
  when defined(vkDebug):
    destroyDebugUtilsMessenger(instance, debugUtilsMessenger)
  destroyInstance(instance)

main()
