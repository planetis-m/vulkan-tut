# https://medium.com/better-programming/optimizing-parallel-reduction-in-metal-for-apple-m1-8e8677b49b01
import opengl, glut, glerrors, glhelpers, glshaderc, std/[strformat, times]

const
  WorkGroupSize = 256 # Shader doesn't work with workgroup <= 64
  NumElements = 1048576
  CoerseFactor = 1024
  NumWorkGroups = NumElements div (WorkGroupSize * 2 * CoerseFactor)

type
  Reduction = object
    program: GLuint
    inputBuffer: GLuint
    outputBuffer: GLuint
    uniformBuffer: GLuint

  ReduceParamsBuffer = object
    arraySize: GLuint
    coerseFactor: GLuint
    padding: array[2, GLuint]

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteBuffers(1, addr x.uniformBuffer)
  glDeleteProgram(x.program)

proc initOpenGLContext() =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

proc initResources(): Reduction =
  # Create and compile the compute shader
  let shaderCode = readFile("shaders/reduce_blocked.comp.glsl")
  result.program = createComputeProgram(shaderCode, "reduce.comp",
      {0.GLuint: WorkGroupSize.GLuint})
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(int32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = 1
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumWorkGroups*sizeof(int32), nil, GL_STATIC_DRAW)
  # Uniform buffer
  let uniform = ReduceParamsBuffer(coerseFactor: CoerseFactor, arraySize: NumElements)
  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, sizeof(uniform), addr uniform, GL_DYNAMIC_DRAW)

proc dispatchComputeShader(resources: Reduction) =
  # Use the program
  glUseProgram(resources.program)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.outputBuffer)
  glBindBufferBase(GL_UNIFORM_BUFFER, 2, resources.uniformBuffer)
  profile("Compute shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(NumWorkGroups, 1, 1)
    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(resources: Reduction): int32 =
  # Read back the results
  result = 0
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.outputBuffer)
  let outputDataPtr = cast[ptr UncheckedArray[int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<NumWorkGroups:
    result += outputDataPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

proc main() =
  var resources: Reduction
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    let result = readResults(resources)
    let duration = cpuTime() - start
    echo "Final reduction result: ", result
    echo &"Total CPU runtime: {duration*1_000:.4f} ms"
  finally:
    cleanup(resources)

main()