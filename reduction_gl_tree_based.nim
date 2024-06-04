import opengl, opengl/glut, std/strutils

const
  WorkGroupSize = 256
  NumElements = 262144 # Max problem size when MAX_COMPUTE_WORK_GROUP_SIZE (1024)
  NumWorkGroups = NumElements div WorkGroupSize

  ShaderCode = """
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

  sharedData[localIdx] = inputData[globalIdx];
  barrier();

  for (uint stride = localSize / 2; stride > 0; stride >>= 1) {
    if (localIdx < stride) {
      sharedData[localIdx] += sharedData[localIdx + stride];
    }
    barrier();
  }

  if (localIdx == 0) {
    outputData[gl_WorkGroupID.x] = sharedData[0];
  }
}
"""

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
    firstReductionProgram: GLuint
    finalReductionProgram: GLuint
    inputBuffer: GLuint
    outputBuffer: GLuint
    resultBuffer: GLuint

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteBuffers(1, addr x.resultBuffer)
  glDeleteProgram(x.finalReductionProgram)
  glDeleteProgram(x.firstReductionProgram)

proc initOpenGLContext() =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  loadExtensions()

proc initResources(): Reduction =
  # Create and compile the compute shader
  result.firstReductionProgram = createComputeProgram(format(ShaderCode, WorkGroupSize).cstring)
  result.finalReductionProgram = createComputeProgram(format(ShaderCode, NumWorkGroups).cstring)
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(float32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = 1
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumWorkGroups*sizeof(float32), nil, GL_STATIC_DRAW)
  # Final result buffer
  result.resultBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, sizeof(float32), nil, GL_STATIC_DRAW)

proc performFirstReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.firstReductionProgram)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.outputBuffer)
  # Dispatch the compute shader
  glDispatchCompute(NumWorkGroups, 1, 1)
  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc performFinalReduction(resources: Reduction) =
  # Use the program
  glUseProgram(resources.finalReductionProgram)
  # Bind the shader storage buffer
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.outputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.resultBuffer)
  # Dispatch the compute shader
  glDispatchCompute(1, 1, 1)
  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResult(outputBuffer: GLuint): float32 =
  # Read back the result
  result = 0
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, outputBuffer)
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(float32), addr result)

proc main() =
  var resources: Reduction
  try:
    initOpenGLContext()
    resources = initResources()
    performFirstReduction(resources)
    performFinalReduction(resources)
    let result = readResult(resources.resultBuffer)
    echo("Final reduction result: ", result)
  finally:
    cleanup(resources)

main()
