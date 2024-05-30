import opengl, opengl/glut, std/[stats, math]

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

proc main =
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
  const M = 1000
  const N = 1000
  # Buffer size for the matrix
  const BufferSize = M*N*sizeof(float32)

  # Create buffer
  var buffer: GLuint
  glGenBuffers(1, buffer.addr)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, BufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)

  # Load the compute shader
  let shaderCode = """
#version 460
#extension GL_ARB_gpu_shader_int64 : require

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout(binding = 0) buffer Res0 {
  float result[];
};

const uint64_t key = 0x87a93f1dc428be57UL;

uint squares32(uint64_t ctr, uint64_t key) {
  uint64_t x = ctr * key;
  uint64_t y = x;
  uint64_t z = y + key;
  x = x * x + y;
  x = (x >> 32u) | (x << 32u); // round 1
  x = x * x + z;
  x = (x >> 32u) | (x << 32u); // round 2
  x = x * x + y;
  x = (x >> 32u) | (x << 32u); // round 3
  return uint((x * x + z) >> 32u); // round 4
}

float rand32(uint64_t ctr, uint64_t key, float max) {
  uint x = squares32(ctr, key);
  uint u = (0x7fU << 23U) | (x >> 9U);
  return (uintBitsToFloat(u) - 1.0) * max;
}

// Generate Gaussian random numbers using the Ratio of Uniforms method.
float normal(uint64_t ctr, uint64_t key, float mu, float sigma) {
  float a, b;
  do {
    a = rand32(ctr, key, 1.0f);
    b = rand32(ctr + 1UL, key, 1.0) * 1.7156 - 0.8573;
    ctr += 2UL; // Increment within the loop to generate a new random number each iteration
  } while (b * b > -4.0f * a * a * log(a));

  return mu + sigma * (b / a);
}

// Main function to execute compute shader
void main() {
  uint idX = gl_GlobalInvocationID.x;
  uint idY = gl_GlobalInvocationID.y;
  uint id = idY * gl_NumWorkGroups.x * gl_WorkGroupSize.x + idX;
  uint64_t ctr = id * 1000UL + 123456789UL;
  float tmp = normal(ctr, key, 0.0, 1.0);
  result[id] = tmp;
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

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer)

  # Dispatch the compute shader
  let numWorkgroupX = ceil(M/workgroupSize.x.float32).GLuint
  let numWorkgroupY = ceil(N/workgroupSize.y.float32).GLuint
  glDispatchCompute(numWorkgroupX, numWorkgroupY, 1)

  # Synchronize and read back the results
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  var rs: RunningStat
  var bufferPtr = cast[ptr array[M*N, float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  for i in 0 ..< M*N:
    rs.push(bufferPtr[i])
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

  doAssert abs(rs.mean) < 0.08, $rs.mean
  doAssert abs(rs.standardDeviation()-1.0) < 0.1
  let bounds = [3.5, 5.0]
  for a in [rs.max, -rs.min]:
    doAssert a >= bounds[0] and a <= bounds[1]
  rs.clear()

  # Clean up
  glDeleteProgram(shaderProgram)
  glDeleteShader(shaderModule)
  glDeleteBuffers(1, buffer.addr)

main()
