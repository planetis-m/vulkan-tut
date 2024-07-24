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

  # Get the OpenGL version string
  let versionString = $cast[cstring](glGetString(GL_VERSION))
  echo "OpenGL Version: ", versionString

  # Load the compute shader
  let shaderCode = readFile("shaders/square.comp.glsl").cstring
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
  const NumElements = 10
  const BufferSize = NumElements*sizeof(int32)

  var inpBuffer, outBuffer: GLuint
  glGenBuffers(1, inpBuffer.addr)
  glGenBuffers(1, outBuffer.addr)

  # Bind the input buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, inpBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Map the input buffer and write data
  var inpBufferPtr = cast[ptr array[NumElements, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0 ..< NumElements:
    inpBufferPtr[i] = int32(i)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, inpBuffer)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, outBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, outBuffer)

  profile("Compute shader dispatch"):
    # Dispatch compute shader
    glDispatchCompute(NumElements, 1, 1)

    # Synchronize and read back the results
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  var outBufferPtr = cast[ptr array[NumElements, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  echo "OUTPUT: ", outBufferPtr[]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, inpBuffer.addr)
  glDeleteBuffers(1, outBuffer.addr)

main()
