import opengl, glut, glhelpers, std/[stats, math]

const
  WorkgroupSize = 32
  NumElements = 100_000
  ShaderCode = """
// https://www.shadertoy.com/view/ctj3Wc
#version 460

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0) buffer Res0 {
  float result[];
};

uint pcg_hash(inout uint rng_state) {
  rng_state = rng_state * 747796405u + 2891336453u;
  uint state = rng_state;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

float rand32(inout uint rng_state, float max) {
  uint x = pcg_hash(rng_state);
  uint u = (0x7fU << 23U) | (x >> 9U);
  return (uintBitsToFloat(u) - 1.0) * max;
}

// Generate Gaussian random numbers using the Marsaglia polar method.
vec2 normal(inout uint rng_state, float mu, float sigma) {
  float u, v, s;
  do {
    u = 2.0 * rand32(rng_state, 1.0) - 1.0;
    v = 2.0 * rand32(rng_state, 1.0) - 1.0;
    s = u * u + v * v;
  } while (s >= 1.0 || s == 0.0);

  float factor = sqrt(-2.0 * log(s) / s);
  return vec2(mu + sigma * (u * factor), mu + sigma * (v * factor));
}

// Main function to execute compute shader
void main() {
  uint id = gl_GlobalInvocationID.x;
  uint rng_state = id;
  vec2 tmp = normal(rng_state, 0.0, 1.0);
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
  var shaderCodeCStr = ShaderCode.cstring
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
    glDispatchCompute(ceil(NumElements/(2*WorkgroupSize.float32)).GLuint, 1, 1)
    # Synchronize and read back the results
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  profile("Map output buffer"):
    var bufferPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))

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
