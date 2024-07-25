import opengl, glut, glhelpers, std/[math, random]

const
  TileSizeA = 64
  TileSizeB = 32
  TileSizeRatio = TileSizeA div TileSizeB

  SpirvBinary = staticRead("build/shaders/matrix_mul_joint.comp.spv")

  M = 1024
  K = 2048
  N = 1024

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
  result.program = createComputeProgram(SpirvBinary, {0.GLuint: TileSizeA.GLuint, 1.GLuint: TileSizeB.GLuint})
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

  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, 3*sizeof(uint32), nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniformBuffer)
  let uniformBufferPtr = cast[ptr UncheckedArray[int32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.int32
  uniformBufferPtr[1] = K.int32
  uniformBufferPtr[2] = N.int32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc dispatchComputeShader(resources: MatrixMultiplication) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.bufferA)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.bufferB)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, resources.bufferC)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  profile("Compute shader dispatch"):
    glDispatchCompute(ceilDiv(M, TileSizeA).GLuint, ceilDiv(N, TileSizeB).GLuint, 1)
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(resources: MatrixMultiplication): seq[float32] =
  result = newSeq[float32](M * N)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.bufferC)
  let bufferCPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<M*N:
    result[i] = bufferCPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

proc computeElement(m, n, p, row, col: int): float32 =
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
    dispatchComputeShader(resources)
    let result = readResults(resources)
    doAssert checkRandomSamples(result, M, K, N, 100_000)
  finally:
    cleanup(resources)

main()
