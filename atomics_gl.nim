import opengl, glut, glhelpers

proc main =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")

  doAssert glInit(), "Failed to load OpenGL"

  # Load the compute shader
  let shaderCode = readFile("shaders/atomics.comp.glsl").cstring
  var shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  glShaderSource(shaderModule, 1, addr shaderCode, nil)
  glCompileShader(shaderModule)

  checkShaderCompilation(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)

  checkProgramLinking(shaderProgram)

  # Create buffers
  const NumTasks = 10000
  const NumWorkers = 12800
  const TaskBufferSize = sizeof(int32) + NumTasks * sizeof(int32)
  const ResultBufferSize = NumWorkers * sizeof(int32)

  var counterBuffer, taskBuffer, resultBuffer: GLuint

  counterBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, TaskBufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var counterPtr = cast[ptr int32](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  counterPtr[] = 0  # Start with task 0
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Initialize task buffer (all tasks initially available)
  taskBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, TaskBufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, taskBuffer)
  var taskBufferPtr = cast[ptr UncheckedArray[int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  taskBufferPtr[0] = NumTasks  # numTasks
  for i in 0 ..< NumTasks:
    taskBufferPtr[i + 1] = 1  # 1 means task is available
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Initialize result buffer
  resultBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, ResultBufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Use the program
  glUseProgram(shaderProgram)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, counterBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, taskBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, resultBuffer)

  profile("Compute shader dispatch"):
    # Dispatch compute shader
    glDispatchCompute(GLuint(NumWorkers div 32), 1, 1)

    # Synchronize
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  # Read and print results
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resultBuffer)
  var resultBufferPtr = cast[ptr array[NumWorkers, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  # echo "Task Allocation Results:"
  # for i in 0 ..< NumWorkers:
  #   echo "Worker ", i, " got task ", resultBufferPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Clean up
  glDeleteBuffers(1, counterBuffer.addr)
  glDeleteBuffers(1, taskBuffer.addr)
  glDeleteBuffers(1, resultBuffer.addr)
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)

main()
