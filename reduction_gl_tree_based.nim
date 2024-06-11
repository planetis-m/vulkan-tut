import opengl, glut, glerrorcheck, std/[strutils, times]

const
  WorkGroupSize = 256
  NumElements = 1048576 # Max problem size when MAX_COMPUTE_WORK_GROUP_SIZE (1024)
  NumWorkGroups = NumElements div WorkGroupSize

  SpirvBinary = staticRead("build/shaders/reduce.spv")

type
  SpecializationConstant = tuple[index, value: GLuint]

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.Glint:
    var len: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetShaderInfoLog(shader, len, nil, cstring(log))
    raise newException(GLError, "Shader compilation error: " & log)

proc checkProgramLinking(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetProgramInfoLog(program, len, nil, cstring(log))
    raise newException(GLError, "Program linking error: " & log)

proc loadShader[N: static int](shaderType: GLenum, spirvBinary: string,
                constants: array[N, SpecializationConstant]): GLuint =
  result = glCreateShader(shaderType)
  if result != 0.GLUint:
    glShaderBinary(1, addr result, GL_SHADER_BINARY_FORMAT_SPIR_V,
                   spirvBinary.cstring, spirvBinary.len.GLsizei)
    let entryPoint = cstring"main"
    when N > 0:
      var indices: array[N, GLuint]
      var values: array[N, GLuint]
      for i, constant in constants.pairs:
        indices[i] = constant.index
        values[i] = constant.value
      glSpecializeShader(result, entryPoint, constants.len.GLuint, indices[0].addr, values[0].addr)
    else:
      glSpecializeShader(result, entryPoint, 0, nil, nil)
    checkShaderCompilation(result)

proc createComputeProgram[N: static int](spirvBinary: string,
                          constants: array[N, SpecializationConstant]): GLuint =
  let module = loadShader(GL_COMPUTE_SHADER, spirvBinary, constants)
  if module != 0.GLUint:
    try:
      result = glCreateProgram()
      if result != 0.GLUint:
        glAttachShader(result, module)
        glLinkProgram(result)
        checkProgramLinking(result)
    finally:
      glDeleteShader(module)

proc createGPUBuffer(target: GLenum, size: GLsizeiptr, data: pointer, usage: GLenum): GLuint =
  glGenBuffers(1, addr result)
  glBindBuffer(target, result)
  glBufferData(target, size, data, usage)

type
  Reduction = object
    firstReductionProgram: GLuint
    finalReductionProgram: GLuint
    inputBuffer: GLuint
    outputBuffer: GLuint
    resultBuffer: GLuint

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteBuffers(1, addr x.resultBuffer)
  glDeleteProgram(x.finalReductionProgram)
  glDeleteProgram(x.firstReductionProgram)

proc initOpenGLContext() =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  doAssert glInit(), "Failed to load OpenGL"

proc initResources(): Reduction =
  # Create and compile the compute shader
  result.firstReductionProgram = createComputeProgram(SpirvBinary, {0.GLuint: WorkGroupSize.GLuint, 1.GLuint: NumElements})
  result.finalReductionProgram = createComputeProgram(SpirvBinary, {0.GLuint: WorkGroupSize.GLuint, 1.GLuint: NumWorkGroups})
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(float32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = 1
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumWorkGroups*sizeof(float32), nil, GL_STATIC_DRAW)
  # Final result buffer
  result.resultBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, sizeof(float32), nil, GL_STATIC_DRAW)

proc performFirstReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.firstReductionProgram)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.outputBuffer)
  # Dispatch the compute shader
  glDispatchCompute(NumWorkGroups, 1, 1)
  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc performFinalReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.finalReductionProgram)
  # Bind the shader storage buffer
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.outputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.resultBuffer)
  # Dispatch the compute shader
  glDispatchCompute(1, 1, 1)
  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResult(resources: Reduction): float32 =
  # Read back the result
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.resultBuffer)
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(float32), addr result)

template ff(f: float, prec: int = 4): string =
  formatFloat(f*1000, ffDecimal, prec) # ms

proc main() =
  var resources: Reduction
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    performFirstReduction(resources)
    performFinalReduction(resources)
    let duration = cpuTime()
    let result = readResult(resources)
    echo "Final reduction result: ", result
    echo "Runtime: ", ff(duration)
  finally:
    cleanup(resources)

main()
