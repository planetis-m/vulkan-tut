#version 460
#extension GL_ARB_gpu_shader_int64 : require

layout(local_size_x_id = 0) in;

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
  uint id = gl_GlobalInvocationID.x;
  uint64_t ctr = id * 1000UL + 123456789UL;
  float tmp = normal(ctr, key, 0.0, 1.0);
  result[id] = tmp;
}
