import opengl, glerrors

type
  SpecializationConstant* = tuple[index, value: GLuint]

proc checkShaderCompilation*(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetShaderInfoLog(shader, len, nil, cstring(log))
    raise newException(GLError, "Shader compilation error: " & log)

proc checkProgramLinking*(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var len: GLint
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr len)
    var log = newString(len)
    glGetProgramInfoLog(program, len, nil, cstring(log))
    raise newException(GLError, "Program linking error: " & log)

proc loadShader*[N: static int](shaderType: GLenum, spirvBinary: string,
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

proc createComputeProgram*[N: static int](spirvBinary: string,
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

proc createGPUBuffer*(target: GLenum, size: GLsizeiptr, data: pointer, usage: GLenum): GLuint =
  glGenBuffers(1, addr result)
  glBindBuffer(target, result)
  glBufferData(target, size, data, usage)
