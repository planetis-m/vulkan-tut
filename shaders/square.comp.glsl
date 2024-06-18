#version 450
layout(local_size_x = 1, local_size_y = 1) in;

layout(std430, binding = 0) readonly buffer lay0 {
  int inbuf[];
};

layout(std430, binding = 1) writeonly buffer lay1 {
  int outbuf[];
};

void main() {
  // Current offset
  const uint id = gl_GlobalInvocationID.x;
  outbuf[id] = inbuf[id] * inbuf[id];
}
