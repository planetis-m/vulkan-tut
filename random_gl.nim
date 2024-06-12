import opengl, glut, glerrors, glhelpers, std/[stats, math]

const
  WorkgroupSize = 32
  NumElements = 100_000
  SpirvBinary = staticRead("build/shaders/rand_normal.comp.spv")

type
  RandomUniform = object
    program: GLuint
    buffer: GLuint

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

proc cleanup(x: RandomUniform) =
  glDeleteBuffers(1, addr x.buffer)
  glDeleteProgram(x.program)

proc initResources(): RandomUniform =
  result.program = createComputeProgram(SpirvBinary, {0.GLuint: WorkGroupSize.GLuint})
  let bufferSize = NumElements*sizeof(float32)
  result.buffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSize, nil, GL_DYNAMIC_DRAW)

proc dispatchComputeShader(resources: RandomUniform) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.buffer)
  profile("Compute shader dispatch"):
    glDispatchCompute(ceilDiv(NumElements, WorkgroupSize).GLuint, 1, 1)
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc checkResults(resources: RandomUniform) =
  var rs: RunningStat
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.buffer)
  let bufferPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<NumElements:
    rs.push(bufferPtr[i])
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  doAssert abs(rs.mean) < 0.08, $rs.mean
  doAssert abs(rs.standardDeviation()-1.0) < 0.1
  let bounds = [3.5, 5.0]
  for a in [rs.max, -rs.min]:
    doAssert a >= bounds[0] and a <= bounds[1]
  rs.clear()

proc main =
  var resources: RandomUniform
  try:
    initOpenGLContext()
    resources = initResources()
    dispatchComputeShader(resources)
    checkResults(resources)
  finally:
    cleanup(resources)

main()
