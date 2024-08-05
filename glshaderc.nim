import shaderc, opengl, glerrors, glhelpers

const WarpSize {.intdefine.} = 64

proc addMacroDefinition*(options: ShadercCompileOptionsT; name: string) {.inline.} =
  addMacroDefinition(options, name.cstring, name.len.csize_t, nil, 0)
proc addMacroDefinition*(options: ShadercCompileOptionsT; name, value: string) {.inline.} =
  addMacroDefinition(options, name.cstring, name.len.csize_t, value.cstring, value.len.csize_t)

proc createShaderModule*(program: GLuint, source: string, kind: ShadercShaderKind,
                         filename: string = "", optimize = false) =
  let compiler = shadercCompilerInitialize()
  let options = shadercCompileOptionsInitialize()
  try:
    setTargetEnv(options, Opengl, 0)
    if optimize:
      setOptimizationLevel(options, Size)
    addMacroDefinition(options, "WARP_SIZE", $WarpSize)
    let module = compileIntoSpv(compiler, source.cstring, source.len.csize_t,
        ComputeShader, filename, "main", options)
    try:
      if module.getCompilationStatus() != Success:
        raise newException(GLError, "Error compiling module: " & $module.getErrorMessage())
      glShaderBinary(1, addr program, GL_SHADER_BINARY_FORMAT_SPIR_V, module.getBytes(),
                     module.getLength().GLsizei)
    finally:
      module.release()
  finally:
    options.release()
    compiler.release()

proc glEnumToShadercShaderKind*(glEnum: GLenum): ShadercShaderKind =
  case glEnum
  of GL_COMPUTE_SHADER:
    ComputeShader
  of GL_VERTEX_SHADER:
    VertexShader
  of GL_TESS_CONTROL_SHADER:
    TessControlShader
  of GL_TESS_EVALUATION_SHADER:
    TessEvaluationShader
  of GL_GEOMETRY_SHADER:
    GeometryShader
  of GL_FRAGMENT_SHADER:
    FragmentShader
  else:
    raise newException(ValueError, "Unknown GLenum value")

proc loadShader*[N: static int](shaderType: GLenum, source, filename: string,
                                constants: array[N, SpecializationConstant]): GLuint =
  result = glCreateShader(shaderType)
  if result != 0.GLUint:
    createShaderModule(result, source, glEnumToShadercShaderKind(shaderType), filename)
    when N > 0:
      var indices: array[N, GLuint]
      var values: array[N, GLuint]
      for i, constant in constants.pairs:
        indices[i] = constant.index
        values[i] = constant.value
      glSpecializeShader(result, "main", constants.len.GLuint, indices[0].addr, values[0].addr)
    else:
      glSpecializeShader(result, "main", 0, nil, nil)
    checkShaderCompilation(result)

proc createComputeProgram*[N: static int](source, filename: string,
                                          constants: array[N, SpecializationConstant]): GLuint =
  let module = loadShader(GL_COMPUTE_SHADER, source, filename, constants)
  if module != 0.GLUint:
    try:
      result = glCreateProgram()
      if result != 0.GLUint:
        glAttachShader(result, module)
        glLinkProgram(result)
        checkProgramLinking(result)
    finally:
      glDeleteShader(module)
