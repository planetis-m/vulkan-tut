#version 430
layout(local_size_x = 256) in; // Define the number of threads per block.

// Binding for the input buffer containing the array of numbers.
layout(std430, binding = 0) buffer InputBuffer {
  int data[];
} inputBuffer;

// Binding for the output buffer to store the prefix sum result.
layout(std430, binding = 1) buffer OutputBuffer {
  int data[];
} outputBuffer;

void main() {
  const uint localId = gl_LocalInvocationID.x;
  const uint globalId = gl_GlobalInvocationID.x;

}
