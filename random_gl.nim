import opengl, glut, std/[stats, math, times, strutils]

const
  WorkgroupSize = 32
  NumElements = 100_000
  SpirvBinary = staticRead("build/shaders/rand_normal.spv")

type
  GLerror = object of Exception
  SpecializationConstant = tuple[index, value: GLuint]

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetShaderInfoLog(shader, len, nil, cstring(log))
    raise newException(GLerror, "Shader compilation error: " & log)

proc checkProgramLinking(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetProgramInfoLog(program, len, nil, cstring(log))
    raise newException(GLerror, "Program linking error: " & log)

proc loadShader[N: static int](shaderType: GLenum, spirvBinary: string,
                constants: array[N, SpecializationConstant]): GLuint =
  result = glCreateShader(shaderType)
  if result != 0.GLUint:
    glShaderBinary(1, addr result, GL_SHADER_BINARY_FORMAT_SPIR_V,
                   spirvBinary.cstring, spirvBinary.len.GLsizei)
    let entryPoint = cstring"main"
    when N > 0:
      var indices: array[N, GLuint]
      var values: array[N, GLuint]
      for i, constant in constants.pairs:
        indices[i] = constant.index
        values[i] = constant.value
      glSpecializeShader(result, entryPoint, constants.len.GLuint, indices[0].addr, values[0].addr)
    else:
      glSpecializeShader(result, entryPoint, 0, nil, nil)
    checkShaderCompilation(result)

proc createComputeProgram[N: static int](spirvBinary: string,
                          constants: array[N, SpecializationConstant]): GLuint =
  let module = loadShader(GL_COMPUTE_SHADER, spirvBinary, constants)
  if module != 0.GLUint:
    try:
      result = glCreateProgram()
      if result != 0.GLUint:
        glAttachShader(result, module)
        glLinkProgram(result)
        checkProgramLinking(result)
    finally:
      glDeleteShader(module)

proc createGPUBuffer(target: GLenum, size: GLsizeiptr, data: pointer, usage: GLenum): GLuint =
  glGenBuffers(1, addr result)
  glBindBuffer(target, result)
  glBufferData(target, size, data, usage)

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

type
  RandomUniform = object
    program: GLuint
    buffer: GLuint

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

template ff(f: float, prec: int = 4): string =
  formatFloat(f*1000, ffDecimal, prec) # ms

proc main =
  var resources: RandomUniform
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    checkResults(resources)
    let duration = cpuTime() - start
    echo "Runtime: ", ff(duration), " ms"
  finally:
    cleanup(resources)

main()
