import opengl, opengl/glut, std/[math, strutils, times, random]

const
  WorkGroupSizeX = 32
  WorkGroupSizeY = 32
  M = 1024
  N = 2048
  P = 1024

  ShaderCode = format("""
#version 460

layout(local_size_x = $1, local_size_y = $2, local_size_z = 1) in;

layout(binding = 0) buffer MatrixA {
  float dataA[];
};

layout(binding = 1) buffer MatrixB {
  float dataB[];
};

layout(binding = 2) buffer MatrixC {
  float dataC[];
};

layout(binding = 3) uniform MatrixSize {
  uint M; // number of rows in A and C
  uint N; // number of columns in A and rows in B
  uint P; // number of columns in B and C
};

void main() {
  uint row = gl_GlobalInvocationID.x;
  uint col = gl_GlobalInvocationID.y;
  if (row < M && col < P) {
    float sum = 0.0;
    for (uint k = 0; k < N; k += 4) {
      vec4 a_tmp = vec4(dataA[row * N + k], dataA[row * N + k+1], dataA[row * N + k+2], dataA[row * N + k+3]);
      sum += a_tmp.x * dataB[k * P + col];
      sum += a_tmp.y * dataB[(k+1) * P + col];
      sum += a_tmp.z * dataB[(k+2) * P + col];
      sum += a_tmp.w * dataB[(k+3) * P + col];
    }
    dataC[row * P + col] = sum;
  }
}
""", WorkGroupSizeX, WorkGroupSizeY)

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

proc loadShader(shaderType: GLenum, source: cstring): GLuint =
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
  MatrixMultiplication = object
    program: GLuint
    bufferA: GLuint
    bufferB: GLuint
    bufferC: GLuint
    uniformBuffer: GLuint

proc cleanup(x: MatrixMultiplication) =
  glDeleteBuffers(1, addr x.bufferA)
  glDeleteBuffers(1, addr x.bufferB)
  glDeleteBuffers(1, addr x.bufferC)
  glDeleteBuffers(1, addr x.uniformBuffer)
  glDeleteProgram(x.program)

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  loadExtensions()

proc initResources(): MatrixMultiplication =
  result.program = createComputeProgram(ShaderCode.cstring)
  let bufferSizeA = M * N * sizeof(float32)
  let bufferSizeB = N * P * sizeof(float32)
  let bufferSizeC = M * P * sizeof(float32)

  result.bufferA = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeA, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferA)
  let bufferAPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<M*N:
    bufferAPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferB = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeB, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferB)
  let bufferBPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<N*P:
    bufferBPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferC = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeC, nil, GL_DYNAMIC_DRAW)

  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, (3 * sizeof(uint32)).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniformBuffer)
  let uniformBufferPtr = cast[ptr UncheckedArray[uint32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.uint32
  uniformBufferPtr[1] = N.uint32
  uniformBufferPtr[2] = P.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc dispatchComputeShader(resources: MatrixMultiplication) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.bufferA)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.bufferB)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, resources.bufferC)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  glDispatchCompute(ceilDiv(M, WorkGroupSizeX).GLuint, ceilDiv(P, WorkGroupSizeY).GLuint, 1)
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(resources: MatrixMultiplication): seq[float32] =
  result = newSeq[float32](M * P)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.bufferC)
  let bufferCPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<M*P:
    result[i] = bufferCPtr[i]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

proc computeElement(m, n, p, row, col: int): float32 =
  result = 0
  for k in 0..<n:
    result += float32(row * n + k + 1) * float32(k * p + col + 1)

proc checkRandomSamples(shaderResult: seq[float32], m, n, p, numSamples: int): bool =
  for i in 0..<numSamples:
    let row = rand(m-1)
    let col = rand(p-1)
    let cpuResult = computeElement(m, n, p, row, col)
    if abs(shaderResult[row * p + col] - cpuResult) >= 1e-5:
      return false
  result = true

proc main() =
  randomize()
  var resources: MatrixMultiplication
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    let result = readResults(resources)
    let duration = cpuTime() - start
    doAssert checkRandomSamples(result, M, N, P, 100)
    echo "Runtime: ", formatFloat(duration*1000, ffDecimal, 4), " ms"
  finally:
    cleanup(resources)

main()
