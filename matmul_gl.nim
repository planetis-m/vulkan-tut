import opengl, glut, glerrorcheck, std/[math, strutils, times, random]

type
  SpecializationConstant = tuple[index, value: GLuint]

const
  WorkGroupSize = 16
  SpirvBinary = staticRead("build/shaders/matrix_mul_tiled.spv")

  M = 1024
  K = 2048
  N = 1024

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.GLint:
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
  MatrixMultiplication = object
    program: GLuint
    bufferA: GLuint
    bufferB: GLuint
    bufferC: GLuint
    uniformBuffer: GLuint

proc cleanup(x: MatrixMultiplication) =
  glDeleteBuffers(1, addr x.bufferA)
  glDeleteBuffers(1, addr x.bufferB)
  glDeleteBuffers(1, addr x.bufferC)
  glDeleteBuffers(1, addr x.uniformBuffer)
  glDeleteProgram(x.program)

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

proc initResources(): MatrixMultiplication =
  result.program = createComputeProgram(SpirvBinary, {0.GLuint: WorkGroupSize.GLuint})
  let bufferSizeA = M * K * sizeof(float32)
  let bufferSizeB = K * N * sizeof(float32)
  let bufferSizeC = M * N * sizeof(float32)

  result.bufferA = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeA, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferA)
  let bufferAPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<M*K:
    bufferAPtr[i] = float32(i)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferB = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeB, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferB)
  let bufferBPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<K*N:
    bufferBPtr[i] = float32(i)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferC = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeC, nil, GL_DYNAMIC_DRAW)

  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, (3 * sizeof(uint32)).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniformBuffer)
  let uniformBufferPtr = cast[ptr UncheckedArray[uint32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.uint32
  uniformBufferPtr[1] = K.uint32
  uniformBufferPtr[2] = N.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc dispatchComputeShader(resources: MatrixMultiplication) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.bufferA)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.bufferB)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, resources.bufferC)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  glDispatchCompute(ceilDiv(M, WorkGroupSize).GLuint, ceilDiv(N, WorkGroupSize).GLuint, 1)
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(resources: MatrixMultiplication): seq[float32] =
  result = newSeq[float32](M * N)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.bufferC)
  let bufferCPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<M*N:
    result[i] = bufferCPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

proc computeElement(m, n, p, row, col: int): float32 =
  # See the "Compute the partial product of each tile" part of the compute shader.
  # Different order of operations between the GPU and the host version
  # results in intermediate rounding errors being introduced
  # and accumulated in a certain order.
  result = 0
  for k in 0..<n:
    result += float32(row * n + k) * float32(k * p + col)

proc checkRandomSamples(shaderResult: seq[float32], m, n, p, numSamples: int): bool =
  for i in 0..<numSamples:
    let row = rand(m-1)
    let col = rand(p-1)
    let cpuResult = computeElement(m, n, p, row, col)
    if abs(shaderResult[row * p + col] - cpuResult) >= 1e-4:
      return false
  result = true

proc main() =
  randomize()
  var resources: MatrixMultiplication
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    let result = readResults(resources)
    let duration = cpuTime() - start
    echo "Runtime: ", formatFloat(duration*1000, ffDecimal, 4), " ms"
    doAssert checkRandomSamples(result, M, K, N, 100)
  finally:
    cleanup(resources)

main()
