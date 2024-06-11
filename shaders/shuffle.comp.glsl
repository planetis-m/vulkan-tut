#version 460
// J-Y Park et al, https://eprint.iacr.org/2023/1889

layout(local_size_x_id = 0) in;

const int HALF_ROUNDS = 10 / 2;
const int KEY_SET_LENGTH = HALF_ROUNDS + 1;

layout(binding = 0) buffer Res0 {
  uint result[];
};

layout(binding = 1) uniform Parameters {
  uint key_set[KEY_SET_LENGTH];
  int width;
};

uint rotate_left(uint x, int bits, int width) {
  return (x << bits) | (x >> (width - bits));
}

uint arrhr(uint x, const uint key_set[KEY_SET_LENGTH], const int width) {
  const uint mask = (1 << width) - 1;
  uint t = x;
  for (int i = 0; i < HALF_ROUNDS; i++) {
    t = (t + key_set[i]) & mask;
    t = rotate_left(t, 1, width);
  }
  uint y = (t + key_set[HALF_ROUNDS]) & mask;
  return y;
}

// Main function to execute compute shader
void main() {
  uint id = gl_GlobalInvocationID.x;
  result[id] = arrhr(id, key_set, width);
}
