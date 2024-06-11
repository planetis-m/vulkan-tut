import
  opengl, glut, glerrorcheck, glhelpers,
  std/[math, strutils, times, random, bitops, tables]

const
  NumElements = 1048576 # 2^20
  WorkgroupSize = 32
  HalfRounds = 10 div 2
  KeySetLength = HalfRounds + 1
  SpirvBinary = staticRead("build/shaders/shuffle.comp.spv")

proc generateRandomKeys(keys: var openarray[uint32], mask: uint32) =
  for i in 0..keys.high:
    keys[i] = rand(uint32) and mask

proc calculateChecksum(x: openarray[uint32]): uint32 =
  result = 0
  for i in 0..x.high:
    result = result + x[i]

proc calculateHistogram(x: openarray[uint32]): CountTable[uint32] =
  result = CountTable[uint32]()
  for i in 0..x.high:
    inc result, x[i]

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"


  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, (3 * sizeof(uint32)).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniformBuffer)
  let uniformBufferPtr = cast[ptr UncheckedArray[uint32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.uint32
  uniformBufferPtr[1] = K.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc main =
  randomize(123)

  # Load the compute shader
  var shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  let shaderCodeCStr = allocCStringArray([shaderCode])
  glShaderSource(shaderModule, 1, shaderCodeCStr, nil)
  deallocCStringArray(shaderCodeCStr)
  glCompileShader(shaderModule)
  checkShaderCompilation(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)
  checkProgramLinking(shaderProgram)

  # Use the program
  glUseProgram(shaderProgram)

  # Create buffers
  const bufferSize = NumElements*sizeof(uint32)

  var buffer: GLuint
  glGenBuffers(1, buffer.addr)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer)

  # Generate random keys
  var keySet: array[KeySetLength, uint32]
  # Calculate the width of the result array length

  const Width = fastLog2(NumElements) # only 2^n elements supported
  generateRandomKeys(keySet, uint32((1 shl Width) - 1))

  # Get the location of the uniform variables
  let keySetLocation = glGetUniformLocation(shaderProgram, "key_set")
  let widthLocation = glGetUniformLocation(shaderProgram, "width")

  # Set uniforms
  glUniform1uiv(keySetLocation, KeySetLength, cast[ptr GLuint](addr keySet))
  glUniform1i(widthLocation, Width.GLint)

  # Dispatch the compute shader
  let t0 = cpuTime()
  glDispatchCompute(ceilDiv(NumElements, workgroupSizeX).GLuint, 1, 1)
  checkGLerror()

  # Synchronize and read back the results
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  let t1 = cpuTime()
  var bufferPtr = cast[ptr array[NumElements, uint32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  let t2 = cpuTime()

  # Checksum and histogram tests
  # let checksum = calculateChecksum(bufferPtr[])
  let histogram = calculateHistogram(bufferPtr[])

  let t3 = cpuTime()
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # doAssert checksum == (NumElements - 1) * NumElements div 2
  doAssert histogram.len == NumElements

  template ff(f: float, prec: int = 4): string =
   formatFloat(f*1000, ffDecimal, prec) # ms

  echo "Process: ", ff(t1-t0), " Map: ", ff(t2-t1), " Read: ", ff(t3-t2)

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, buffer.addr)

main()
