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

  # # Use the program
  glUseProgram(shaderProgram)

  # Create buffers
  const NumTasks = 100
  const NumWorkers = 128
  const TaskBufferSize = NumTasks * sizeof(int32)
  const ResultBufferSize = NumWorkers * sizeof(int32)

  var taskBuffer, resultBuffer, nextTaskBuffer: GLuint
  glGenBuffers(1, taskBuffer.addr)
  glGenBuffers(1, resultBuffer.addr)
  glGenBuffers(1, nextTaskBuffer.addr)

  # Initialize task buffer (all tasks initially available)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, taskBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, TaskBufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var taskBufferPtr = cast[ptr array[NumTasks, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0 ..< NumTasks:
    taskBufferPtr[i] = 1  # 1 means task is available
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, taskBuffer)

  # Initialize result buffer
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resultBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, ResultBufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resultBuffer)

  # Initialize nextTask buffer
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, nextTaskBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(int32).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var nextTaskPtr = cast[ptr int32](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  nextTaskPtr[] = 0  # Start with task 0
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, nextTaskBuffer)

  # Set the uniform for the number of tasks
  let numTasksLocation = glGetUniformLocation(shaderProgram, "numTasks")
  glUniform1i(numTasksLocation, NumTasks.GLint)

  profile("Compute shader dispatch"):
    # Dispatch compute shader
    glDispatchCompute(GLuint(NumWorkers div 32), 1, 1)

    # Synchronize
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  # Read and print results
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resultBuffer)
  var resultBufferPtr = cast[ptr array[NumWorkers, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  echo "Task Allocation Results:"
  for i in 0 ..< NumWorkers:
    echo "Worker ", i, " got task ", resultBufferPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Clean up
  glDeleteBuffers(1, taskBuffer.addr)
  glDeleteBuffers(1, resultBuffer.addr)
  glDeleteBuffers(1, nextTaskBuffer.addr)
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)

main()
