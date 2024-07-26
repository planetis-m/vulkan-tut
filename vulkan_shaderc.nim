import vulkan, vulkan_wrapper, shaderc

export ShadercShaderKind

proc createShaderModule*(device: VkDevice, source: string,
    kind: ShadercShaderKind, filename: string, optimize = false,
    apiVersion = vkApiVersion1_3.uint32): VkShaderModule =
  let compiler = shadercCompilerInitialize()
  let options = shadercCompileOptionsInitialize()
  try:
    setTargetEnv(options, Vulkan, apiVersion)
    if optimize:
      setOptimizationLevel(options, Size)
    let module = compileIntoSpv(compiler, source.cstring, source.len.csize_t,
      kind, filename, "main", options)
    try:
      if module.getCompilationStatus() != Success:
        raise newException(ValueError, "Error compiling module - " & $module.getErrorMessage())
      let shaderModuleCreateInfo = newVkShaderModuleCreateInfo(
        code = toOpenArray(module.getBytes(), 0, module.getLength().int - 1)
      )
      result = createShaderModule(device, shaderModuleCreateInfo)
    finally:
      module.release()
  finally:
    options.release()
    compiler.release()
