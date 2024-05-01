import opengl, opengl/glut

proc main =
  # Create an OpenGL context and window
  var argc: cint = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")

  loadExtensions()

  # Get the OpenGL version string
  let versionString = $cast[cstring](glGetString(GL_VERSION))
  echo "OpenGL Version: ", versionString

  # Create buffers
  const NumElements = 10
  const BufferSize = NumElements*sizeof(int32)

  var inBuffer, outBuffer: GLuint
  glGenBuffers(1, inBuffer.addr)
  glGenBuffers(1, outBuffer.addr)

  # Bind the input buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, inBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Map the input buffer and write data
  var inBufferPtr = cast[ptr array[NumElements, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0 ..< NumElements:
    inBufferPtr[i] = int32(i)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, outBuffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Load the compute shader
  let shaderCode = readFile("shaders/shader.comp")
  var shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  var shaderCodeCStr = allocCStringArray([shaderCode])
  glShaderSource(shaderModule, 1, shaderCodeCStr, nil)
  glCompileShader(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)

  # Bind the shader storage buffers
  glUseProgram(shaderProgram)
  let inBufferIndex = glGetProgramResourceIndex(shaderProgram, GL_SHADER_STORAGE_BLOCK, "lay0")
  let outBufferIndex = glGetProgramResourceIndex(shaderProgram, GL_SHADER_STORAGE_BLOCK, "lay1")

  glShaderStorageBlockBinding(shaderProgram, inBufferIndex, 0)
  glShaderStorageBlockBinding(shaderProgram, outBufferIndex, 1)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, inBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, outBuffer)

  # Dispatch the compute shader
  glDispatchCompute(NumElements, 1, 1)

  # Synchronize and read back the results
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  var outBufferPtr = cast[ptr array[NumElements, int32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  echo "OUTPUT: ", outBufferPtr[]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, inBuffer.addr)
  glDeleteBuffers(1, outBuffer.addr)

main()
