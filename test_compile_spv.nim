import shaderc

let compiler = shadercCompilerInitialize()
let options = shadercCompileOptionsInitialize()
setTargetEnv(options, Opengl, 0)
if optimize:
  setOptimizationLevel(options, Size)
let shaderCode = readFile("shaders/atomics.comp.glsl")
let module = compileIntoSpv(compiler, shaderCode.cstring, shaderCode.len.csize_t,
    ComputeShader, "atomics.comp.glsl", "main", options)
if module.getCompilationStatus() != Success:
  quit("Error compiling module - " & $module.getErrorMessage())
module.release()
options.release()
compiler.release()
