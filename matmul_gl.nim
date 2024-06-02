import opengl, opengl/glut, std/[math, strutils, times, random]

const
  workgroupSize = (x: 32, y: 32)

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.Glint:
    var length: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
    if length > 0:
      var log = newString(length)
      glGetShaderInfoLog(shader, length, nil, cstring(log))
      echo "Shader compilation error: ", log
    else:
      echo "Unknown shader compilation error"
  else:
    echo "Shader compiled successfully"

proc checkProgramLinking(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.GLint:
    var length: GLint
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, addr length)
    if length > 0:
      var log = newString(length)
      glGetProgramInfoLog(program, length, nil, cstring(log))
      echo "Program linking error: ", log
    else:
      echo "Unknown program linking error"
  else:
    echo "Program linked successfully"

proc computeElement(m, n, p, row, col: int): float32 =
  result = 0
  for k in 0..<n:
    result += float32(row * n + k + 1) * float32(k * p + col + 1)

proc checkRandomSamples(shaderResult: openarray[float32],
    m, n, p, numSamples: int): bool =
  result = true
  for i in 0..<numSamples:
    let row = rand(m-1)
    let col = rand(p-1)
    let cpuResult = computeElement(m, n, p, row, col)
    if abs(shaderResult[row * p + col] - cpuResult) >= 1e-5:
      return false

proc main =
  randomize()
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")

  loadExtensions()

  # Get the OpenGL version string
  let versionString = $cast[cstring](glGetString(GL_VERSION))
  echo "OpenGL Version: ", versionString

  # Matrix dimensions
  const M = 1024
  const N = 3072
  const P = 1024

  # Create buffers
  var bufferA, bufferB, bufferC: GLuint
  glGenBuffers(1, bufferA.addr)
  glGenBuffers(1, bufferB.addr)
  glGenBuffers(1, bufferC.addr)

  # Buffer size for each matrix
  let bufferSizeA = M * N * sizeof(float32)
  let bufferSizeB = N * P * sizeof(float32)
  let bufferSizeC = M * P * sizeof(float32)

  # Bind and initialize buffer A
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferA)
  glBufferData(GL_SHADER_STORAGE_BUFFER, bufferSizeA.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var bufferAPtr = cast[ptr array[M * N, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0 ..< M * N:
    bufferAPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Bind and initialize buffer B
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferB)
  glBufferData(GL_SHADER_STORAGE_BUFFER, bufferSizeB.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var bufferBPtr = cast[ptr array[N * P, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0 ..< N * P:
    bufferBPtr[i] = float32(i + 1)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  # Bind and initialize buffer C (output)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, bufferC)
  glBufferData(GL_SHADER_STORAGE_BUFFER, bufferSizeC.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Uniform buffer for matrix dimensions
  var uniformBuffer: GLuint
  glGenBuffers(1, uniformBuffer.addr)
  glBindBuffer(GL_UNIFORM_BUFFER, uniformBuffer)
  glBufferData(GL_UNIFORM_BUFFER, (3 * sizeof(uint32)).GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  var uniformBufferPtr = cast[ptr array[3, uint32]](glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  uniformBufferPtr[0] = M.uint32
  uniformBufferPtr[1] = N.uint32
  uniformBufferPtr[2] = P.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, uniformBuffer)

  # Load the compute shader
  let shaderCode = """
#version 460

layout(local_size_x = 32, local_size_y = 32) in;

layout(binding = 0) buffer MatrixA {
  float dataA[];
};

layout(binding = 1) buffer MatrixB {
  float dataB[];
};

layout(binding = 2) buffer MatrixC {
  float dataC[];
};

layout(std140, binding = 3) uniform MatrixSize {
  uint M; // number of rows in A and C
  uint N; // number of columns in A and rows in B
  uint P; // number of columns in B and C
};

void main() {
  uint row = gl_GlobalInvocationID.x;
  uint col = gl_GlobalInvocationID.y;

  if (row >= M || col >= P) {
    return;
  }

  float sum = 0.0;
  for (uint k = 0; k < N; ++k) {
    sum += dataA[row * N + k] * dataB[k * P + col];
  }

  dataC[row * P + col] = sum;
}
"""
  var shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  var shaderCodeCStr = allocCStringArray([shaderCode])
  glShaderSource(shaderModule, 1, shaderCodeCStr, nil)
  deallocCStringArray(shaderCodeCStr)
  glCompileShader(shaderModule)

  checkShaderCompilation(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)

  checkProgramLinking(shaderProgram)

  # Bind the shader storage buffers
  glUseProgram(shaderProgram)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, bufferA)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, bufferB)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, bufferC)

  let t0 = cpuTime()
  # Dispatch the compute shader
  glDispatchCompute(ceilDiv(M, workgroupSize.x).GLuint, ceilDiv(P, workgroupSize.y).GLuint, 1)

  # Synchronize and read back the results
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  let t1 = cpuTime()
  var bufferCPtr = cast[ptr array[M * P, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  let t2 = cpuTime()
  doAssert checkRandomSamples(bufferCPtr[], M, N, P, 100)
  let t3 = cpuTime()
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  template ff(f: float, prec: int = 4): string =
   formatFloat(f*1000, ffDecimal, prec) # ms

  echo ("Process: ", ff(t1-t0), "Map: ", ff(t2-t1), "Read: ", ff(t3-t2))

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, bufferA.addr)
  glDeleteBuffers(1, bufferB.addr)
  glDeleteBuffers(1, bufferC.addr)

main()
