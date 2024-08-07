import opengl, glut, glhelpers, std/[stats, math]

const
  WorkgroupSize = 32
  NumElements = 100_000
  ShaderCode = """
#version 460
#extension GL_ARB_gpu_shader_int64 : require

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

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

// Generate Gaussian random numbers using the Marsaglia polar method.
vec2 normal(uint64_t ctr, uint64_t key, float mu, float sigma) {
  float u, v, s;
  do {
    u = 2.0 * rand32(ctr, key, 1.0) - 1.0;
    v = 2.0 * rand32(ctr + 1UL, key, 1.0) - 1.0;
    s = u * u + v * v;
    ctr += 2UL; // Increment within the loop to generate a new random number each iteration
  } while (s >= 1.0 || s == 0.0);

  float factor = sqrt(-2.0 * log(s) / s);
  return vec2(mu + sigma * (u * factor), mu + sigma * (v * factor));
}

// Main function to execute compute shader
void main() {
  uint id = gl_GlobalInvocationID.x;
  uint64_t ctr = id * 1000UL + 123456789UL;
  vec2 tmp = normal(ctr, key, 0.0, 1.0);
  result[2 * id] = tmp[0];
  result[2 * id + 1] = tmp[1];
}
"""

proc main =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")

  doAssert glInit(), "Failed to load OpenGL"

  # Get the OpenGL version string
  let versionString = $cast[cstring](glGetString(GL_VERSION))
  echo "OpenGL Version: ", versionString

  # Load the compute shader
  var shaderModule = glCreateShader(GL_COMPUTE_SHADER)
  let shaderCodeCStr = ShaderCode.cstring
  glShaderSource(shaderModule, 1, addr shaderCodeCStr, nil)
  glCompileShader(shaderModule)

  checkShaderCompilation(shaderModule)

  # Create the shader program
  var shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, shaderModule)
  glLinkProgram(shaderProgram)

  checkProgramLinking(shaderProgram)

  # Use the program
  glUseProgram(shaderProgram)

  # Create buffers
  let bufferSize = NumElements*sizeof(float32)

  var buffer: GLuint
  glGenBuffers(1, buffer.addr)

  # Bind the output buffer and allocate memory
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer)
  glBufferData(GL_SHADER_STORAGE_BUFFER, bufferSize.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer)

  profile("Compute shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(ceilDiv(NumElements, 2*WorkgroupSize).GLuint, 1, 1)
    # Synchronize and read back the results
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  profile("Map output buffer"):
    let bufferPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))

  var rs: RunningStat
  for i in 0 ..< NumElements:
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
