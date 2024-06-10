import opengl, opengl/glut, std/[math, strutils, times, random]

const
  WorkGroupSize = 16
  M = 1024
  K = 2048
  N = 1024

  ShaderCode = format("""
#version 460

layout(local_size_x = $1, local_size_y = $1, local_size_z = 1) in;

layout(binding = 0) buffer ABuffer {
  float A[];
};

layout(binding = 1) buffer BBuffer {
  float B[];
};

layout(binding = 2) buffer CBuffer {
  float C[];
};

layout(binding = 3) uniform Parameters {
  int M;
  int K;
  int N;
};

const uint TILE_SIZE = $1;

shared float sharedA[TILE_SIZE * TILE_SIZE];
shared float sharedB[TILE_SIZE * TILE_SIZE];

void main() {
  uint localRow = gl_LocalInvocationID.x;
  uint localCol = gl_LocalInvocationID.y;
  uint globalRow = gl_WorkGroupID.x * gl_WorkGroupSize.x + localRow;
  uint globalCol = gl_WorkGroupID.y * gl_WorkGroupSize.y + localCol;

  float sum = 0.0;

  for (uint tileIndex = 0; tileIndex < K / TILE_SIZE; tileIndex++) {
    // Load tiles into shared memory
    if (globalRow < M && (tileIndex * TILE_SIZE + localCol) < K) {
      sharedA[localRow * TILE_SIZE + localCol] = A[globalRow * K + tileIndex * TILE_SIZE + localCol];
    } else {
      sharedA[localRow * TILE_SIZE + localCol] = 0.0;
    }

    if (globalCol < N && (tileIndex * TILE_SIZE + localRow) < K) {
      sharedB[localRow * TILE_SIZE + localCol] = B[(tileIndex * TILE_SIZE + localRow) * N + globalCol];
    } else {
      sharedB[localRow * TILE_SIZE + localCol] = 0.0;
    }

    // Wait for both tiles to be loaded before doing computation
    barrier();

    // Compute the partial product for this tile
    for (uint j = 0; j < TILE_SIZE; j += 4) {
      vec4 tmpA = vec4(sharedA[localRow * TILE_SIZE + j], sharedA[localRow * TILE_SIZE + j+1], sharedA[localRow * TILE_SIZE + j+2], sharedA[localRow * TILE_SIZE + j+3]);
      sum += tmpA.x * sharedB[j * TILE_SIZE + localCol];
      sum += tmpA.y * sharedB[(j+1) * TILE_SIZE + localCol];
      sum += tmpA.z * sharedB[(j+2) * TILE_SIZE + localCol];
      sum += tmpA.w * sharedB[(j+3) * TILE_SIZE + localCol];
    }

    // Wait for all threads to finish using current tiles before loading new tiles
    barrier();
  }

  if (globalRow < M && globalCol < N) {
    C[globalRow * N + globalCol] = sum;
  }
}

""", WorkGroupSize)

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
  let bufferSizeA = M * K * sizeof(float32)
  let bufferSizeB = K * N * sizeof(float32)
  let bufferSizeC = M * N * sizeof(float32)

  result.bufferA = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeA, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferA)
  let bufferAPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<M*K:
    bufferAPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferB = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeB, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.bufferB)
  let bufferBPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<K*N:
    bufferBPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  result.bufferC = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSizeC, nil, GL_DYNAMIC_DRAW)

  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, (3 * sizeof(uint32)).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniformBuffer)
  let uniformBufferPtr = cast[ptr UncheckedArray[uint32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.uint32
  uniformBufferPtr[1] = K.uint32
  uniformBufferPtr[2] = N.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc dispatchComputeShader(resources: MatrixMultiplication) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.bufferA)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, resources.bufferB)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, resources.bufferC)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  glDispatchCompute(ceilDiv(M, WorkGroupSize).GLuint, ceilDiv(N, WorkGroupSize).GLuint, 1)
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc readResults(resources: MatrixMultiplication): seq[float32] =
  result = newSeq[float32](M * N)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.bufferC)
  let bufferCPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0..<M*N:
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
    echo "Runtime: ", formatFloat(duration*1000, ffDecimal, 4), " ms"
    doAssert checkRandomSamples(result, M, K, N, 100)
  finally:
    cleanup(resources)

main()
