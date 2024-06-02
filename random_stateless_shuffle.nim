import opengl, opengl/glut, std/[math, strutils, times, random, bitops, tables]

const
  workgroupSizeX = 32

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

proc generateRandomKeys(keys: var openarray[uint32], width: int) =
  for i in 0..keys.high:
    keys[i] = rand(uint32) and (1'u32 shl width) - 1'u32

proc calculateChecksum(x: openarray[uint32]): uint32 =
  result = 0
  for i in 0..x.high:
    result = result + x[i]

proc calculateHistogram(x: openarray[uint32]): CountTable[uint32] =
  result = CountTable[uint32]()
  for i in 0..x.high:
    inc result, x[i]

proc main =
  randomize(123)
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

  # Create buffers
  const NumElements = 1048576 # 2^20
  const BufferSize = NumElements*sizeof(uint32)

  var buffer: GLuint
  glGenBuffers(1, buffer.addr)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Load the compute shader
  let shaderCode = """
// J.-Y. Park et al., "Fully Parallel, One-Cycle Random Shuffling for Efficient
// Countermeasure in Post-Quantum Cryptography," Cryptology ePrint Archive,
// Report 2023/1889, 2023. [Online]. Available: https://eprint.iacr.org/2023/1889
#version 460

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

const int ROUNDS = 10;
const int KEY_SET_LENGTH = ROUNDS / 2 + 1;

layout(binding = 0) buffer Res0 {
  uint result[];
};

uniform uint key_set[KEY_SET_LENGTH];
uniform int width;

uint rotate_left(uint x, int bits, int width) {
  return (x << bits) | (x >> (width - bits));
}

uint arrhr(uint x, const uint key_set[KEY_SET_LENGTH], int rounds, int width) {
  uint t = x;
  for (int i = 0; i < rounds / 2; i++) {
    t = (t + key_set[i]) & ((1 << width) - 1);
    t = rotate_left(t, 1, width);
  }
  uint y = (t + key_set[rounds / 2]) & ((1 << width) - 1);
  return y;
}

// Main function to execute compute shader
void main() {
  uint id = gl_GlobalInvocationID.x;
  result[id] = arrhr(id, key_set, ROUNDS, width);
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

  # Generate random keys
  const Rounds = 10
  const KeySetLength = Rounds div 2 + 1

  var keySet: array[KeySetLength, uint32]
  # Calculate the width of the result array length

  let width = fastLog2(NumElements)
  generateRandomKeys(keySet, width)

  # Get the location of the uniform variables
  let keySetLocation = glGetUniformLocation(shaderProgram, "key_set")
  let widthLocation = glGetUniformLocation(shaderProgram, "width")

  # Set uniforms
  glUniform1uiv(keySetLocation, KeySetLength, cast[ptr GLuint](addr keySet))
  glUniform1i(widthLocation, width.GLint)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer)

  let t0 = cpuTime()
  # Dispatch the compute shader
  const numWorkgroupX = ceilDiv(NumElements, workgroupSizeX).GLuint
  glDispatchCompute(numWorkgroupX, 1, 1)
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

  # doAssert checksum == NumElements * (NumElements - 1) div 2
  doAssert histogram.len == NumElements
  doAssert histogram.largest.val == 1

  template ff(f: float, prec: int = 4): string =
   formatFloat(f*1000, ffDecimal, prec) # ms

  echo ("Process: ", ff(t1-t0), "Map: ", ff(t2-t1), "Read: ", ff(t3-t2))

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, buffer.addr)

main()
