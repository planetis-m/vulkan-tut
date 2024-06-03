import opengl, opengl/glut, std/strutils

const
  WorkGroupSize = 256
  ShaderCode = format("""
#version 460

layout(local_size_x = $1, local_size_y = 1, local_size_z = 1) in;

shared float sharedData[$1];

layout(binding = 0) buffer InputBuffer {
  float inputData[];
};

layout(binding = 1) buffer OutputBuffer {
  float outputData[];
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint globalIdx = gl_GlobalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x;

  uint stride = localSize / 2;
  sharedData[localIdx] = inputData[globalIdx] + inputData[globalIdx + stride];
  barrier();

  stride >>= 1;
  for (; stride > 0; stride >>= 1) {
    if (localIdx < stride) {
      sharedData[localIdx] += sharedData[localIdx + stride];
    }
    barrier();
  }

  if (localIdx == 0) {
    outputData[gl_WorkGroupID.x] = sharedData[0];
  }
}
""", WorkGroupSize)

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.Glint:
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

proc loadShader(shaderType: GLenum, source: cstring): GLuint =
  # Create and compile the compute shader
  result = glCreateShader(shaderType)
  if result != 0.GLUint:
    glShaderSource(result, 1, cast[cstringArray](addr source), nil)
    glCompileShader(result)
    checkShaderCompilation(result)

proc createComputeProgram(computeSource: cstring): GLuint =
  let module = loadShader(GL_COMPUTE_SHADER, computeSource)
  if module != 0.GLUint:
    try:
      result = glCreateProgram()
      # Create the shader program and link the compute shader
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
  checkGLerror()

type
  Reduction = object
    program: GLuint
    inpBuffer: GLuint
    outBuffer: GLuint

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inpBuffer)
  glDeleteBuffers(1, addr x.outBuffer)
  glDeleteProgram(x.program)

proc main() =
  var x: Reduction
  try:
    # Create an OpenGL context and window
    var argc: int32 = 0
    glutInit(addr argc, nil)
    glutInitDisplayMode(GLUT_DOUBLE)
    glutInitWindowSize(640, 480)
    glutInitWindowPosition(50, 50)
    discard glutCreateWindow("OpenGL Compute")

    loadExtensions()

    # Create and compile the compute shader
    x.program = createComputeProgram(ShaderCode.cstring)

    # Use the program
    glUseProgram(x.program)

    # Initialize input data
    const numElements = 1024
    const numWorkGroups = numElements div WorkGroupSize

    # Generate and bind SSBOs
    x.inpBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, numElements*sizeof(float32),
        nil, GL_STATIC_DRAW)

    let inpDataPtr = cast[ptr array[numElements, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
    for i in 0..<numElements:
      inpDataPtr[i] = float32(i + 1)
    discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, x.inpBuffer)

    # Output buffer
    x.outBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, numWorkGroups*sizeof(float32),
        nil, GL_STATIC_DRAW)
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, x.outBuffer)

    # Dispatch the compute shader
    glDispatchCompute(numWorkGroups.GLuint, 1, 1)

    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

    # Read back the results
    var outData: array[numWorkGroups, float32]
    glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, numWorkGroups*sizeof(float32), addr outData[0])

    # Perform final reduction on the CPU if necessary
    var result: float32 = 0
    for i in 0 ..< numWorkGroups:
      result = result + outData[i]
    echo("Final reduction result: ", result)

  finally:
    cleanup(x)

main()
