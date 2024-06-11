import opengl, opengl/glut, std/[stats, math]

const
  WorkgroupSizeX = 32
  SpirvBinary = staticRead("build/shaders/rand_normal.spv")

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.Glint:
    var len: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetShaderInfoLog(shader, len, nil, cstring(log))
    echo "Shader compilation error: ", log

proc checkProgramLinking(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetProgramInfoLog(program, len, nil, cstring(log))
    echo "Program linking error: ", log

proc main =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  loadExtensions()

  # Get the OpenGL version string
  let versionString = $cast[cstring](glGetString(GL_VERSION))
  echo "OpenGL Version: ", versionString

  # Load the compute shader
  let spirvLength = SpirvBinary.len.GLsizei
  let constantIndex = 0.GLuint
  let constantValue = WorkGroupSizeX.GLuint
  let shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  glShaderBinary(1, addr shaderModule, GL_SHADER_BINARY_FORMAT_SPIR_V, SpirvBinary.cstring, spirvLength)
  glSpecializeShader(shaderModule, cstring"main", 1, addr constantIndex, addr constantValue)

  # let shaderCode = readFile("shaders/rand_normal.comp")
  # glShaderSource(shaderModule, 1, cast[cstringArray](addr shaderCode.cstring), nil)
  # glCompileShader(shaderModule)

  checkShaderCompilation(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)

  checkProgramLinking(shaderProgram)

  # Use the program
  glUseProgram(shaderProgram)

  # Matrix dimensions
  const NumElements = 100_000
  # Buffer size for the matrix
  const BufferSize = NumElements*sizeof(float32)

  # Create buffer
  var buffer: GLuint
  glGenBuffers(1, buffer.addr)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer)

  # Dispatch the compute shader
  let numWorkgroupX = ceil(NumElements/WorkgroupSizeX.float32).GLuint
  glDispatchCompute(numWorkgroupX, 1, 1)

  # Synchronize and read back the results
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  var rs: RunningStat
  var bufferPtr = cast[ptr array[NumElements, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0 ..< NumElements:
    rs.push(bufferPtr[i])
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  doAssert abs(rs.mean) < 0.08, $rs.mean
  doAssert abs(rs.standardDeviation()-1.0) < 0.1
  let bounds = [3.5, 5.0]
  for a in [rs.max, -rs.min]:
    doAssert a >= bounds[0] and a <= bounds[1]
  rs.clear()

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, buffer.addr)

main()
