import opengl, glut, glhelpers, glshaderc, std/[strformat, times]

const
  WorkGroupSize = 256 # Shader doesn't work with workgroup <= 64
  NumElements = 1048576
  CoarseFactor = 1024
  NumWorkGroups = NumElements div (WorkGroupSize * 2 * CoarseFactor)

type
  Reduction = object
    program: GLuint
    inputBuffer: GLuint
    outputBuffer: GLuint
    resultBuffer: GLuint
    uniformBuffer: GLuint

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteBuffers(1, addr x.resultBuffer)
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
  doAssert glInit(), "Failed to load OpenGL"

proc initResources(): Reduction =
  # Create and compile the compute shader
  let shaderCode = readFile("shaders/reduce.comp.glsl")
  result.program = createComputeProgram(shaderCode, "reduce.comp", {0.GLuint: WorkGroupSize.GLuint})
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(int32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = 1
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumWorkGroups*sizeof(int32), nil, GL_STATIC_DRAW)
  # Final result buffer
  result.resultBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, sizeof(int32), nil, GL_STATIC_DRAW)
  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, sizeof(uint32), nil, GL_DYNAMIC_DRAW)

proc performFirstReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.program)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.outputBuffer)
  # Update the uniform data
  let uniformData: uint32 = NumElements
  glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(uint32), addr uniformData)
  glBindBufferBase(GL_UNIFORM_BUFFER, 2, resources.uniformBuffer)
  profile("First reduction compute shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(NumWorkGroups, 1, 1)
    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc performFinalReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.program)
  # Bind the shader storage buffer
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.outputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.resultBuffer)
  # Update the uniform data
  let uniformData: uint32 = NumWorkGroups
  glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(uint32), addr uniformData)
  glBindBufferBase(GL_UNIFORM_BUFFER, 2, resources.uniformBuffer)
  profile("Final reduction compute shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(1, 1, 1)
    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResult(resources: Reduction): int32 =
  # Read back the result
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.resultBuffer)
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(int32), addr result)

proc main() =
  var resources: Reduction
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    performFirstReduction(resources)
    performFinalReduction(resources)
    let duration = cpuTime() - start
    let result = readResult(resources)
    echo "Final reduction result: ", result
    echo &"Total CPU runtime: {duration*1_000:.4f} ms"
  finally:
    cleanup(resources)

main()
