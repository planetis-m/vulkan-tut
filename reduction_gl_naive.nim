import opengl, opengl/glut, std/[strutils, times]

const
  WorkGroupSize = 256
  NumElements = 1048576
  NumElementsPerThread = 1024
  NumWorkGroups = NumElements div NumElementsPerThread div WorkGroupSize

const
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

uniform uint n;

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x;
  uint globalIdx = gl_WorkGroupID.x * (localSize * 2) + localIdx;
  uint gridSize = localSize * 2 * gl_NumWorkGroups.x;

  sharedData[localIdx] = 0;
  while (globalIdx < n) {
    sharedData[localIdx] += inputData[globalIdx] + inputData[globalIdx + localSize];
    globalIdx += gridSize;
  }
  barrier();

  for (uint stride = localSize / 2; stride > 0; stride >>= 1) {
    if (localIdx < stride) {
      sharedData[localIdx] += sharedData[localIdx + stride];
    }
    memoryBarrierShared();
  }

  // Final reduction within each subgroup
  if (localIdx < 64) {
    sharedData[localIdx] += sharedData[localIdx + 64];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 32];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 16];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 8];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 4];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 2];
    memoryBarrierShared();
    sharedData[localIdx] += sharedData[localIdx + 1];
    memoryBarrierShared();
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
    inputBuffer: GLuint
    outputBuffer: GLuint

proc cleanup(x: Reduction) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteProgram(x.program)

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
  result.program = createComputeProgram(ShaderCode.cstring)
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(float32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = 1
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumWorkGroups*sizeof(float32), nil, GL_STATIC_DRAW)

proc dispatchComputeShader(resources: Reduction) =
  # Use the program
  glUseProgram(resources.program)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.outputBuffer)
  # Get the location of the uniform variable and set it
  let nLoc = glGetUniformLocation(resources.program, "n")
  glUniform1ui(nLoc, NumElementsPerThread)
  # Dispatch the compute shader
  glDispatchCompute(NumWorkGroups, 1, 1)
  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(outputBuffer: GLuint): float32 =
  # Read back the results
  result = 0
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, outputBuffer)
  let outputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<NumWorkGroups:
    result += outputDataPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

template ff(f: float, prec: int = 4): string =
  formatFloat(f*1000, ffDecimal, prec) # ms

proc main() =
  var resources: Reduction
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    let result = readResults(resources.outputBuffer)
    let duration = cpuTime() - start
    echo "Final reduction result: ", result
    echo "Runtime: ", ff(duration)
  finally:
    cleanup(resources)

main()
