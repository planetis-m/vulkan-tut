#version 430

layout(local_size_x_id = 0) in;
layout(constant_id = 0) const uint SECTION_SIZE = 32;

// Uniform for array size
layout(location = 0) uniform uint arraySize;

// Input and output buffers
layout(std430, binding = 0) buffer InputBuffer {
  float inputArray[];
};

layout(std430, binding = 1) buffer OutputBuffer {
  float prefixSums[];
};

// Shared memory for parallel reduction
shared float sharedData[SECTION_SIZE];

void main() {
  // Get global and local indices
  uint globalIndex = gl_GlobalInvocationID.x;
  uint localIndex = gl_LocalInvocationID.x;

  // Load data into shared memory
  if (globalIndex < arraySize) {
    sharedData[localIndex] = inputArray[globalIndex];
  } else {
    sharedData[localIndex] = 0.0f;
  }

  // Kogge-Stone parallel scan
  for (uint stride = 1; stride < gl_WorkGroupSize.x; stride *= 2) {
    memoryBarrierShared();
    barrier();

    float currentSum;
    if (localIndex >= stride) {
      currentSum = sharedData[localIndex] + sharedData[localIndex - stride];
    }

    memoryBarrierShared();
    barrier();

    if (localIndex >= stride) {
      sharedData[localIndex] = currentSum;
    }
  }

  // Write result to output buffer
  if (globalIndex < arraySize) {
    prefixSums[globalIndex] = sharedData[localIndex];
  }
}
