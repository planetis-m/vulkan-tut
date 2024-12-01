#version 430

layout(local_size_x_id = 0) in;
layout(constant_id = 0) const uint SECTION_SIZE = 32;

layout(std140, binding = 3) uniform ScanParams {
  uint arraySize;
  uint isExclusive;
};

// Input buffer
layout(std430, binding = 0) buffer InputBuffer {
  float inputData[];
};

layout(std430, binding = 1) buffer OutputBuffer {
  float outputData[]; // Size = arraySize, stores intermediate results
};

layout(std430, binding = 2) buffer BlockSumsBuffer {
  float partialSums[]; // Size = numWorkGroups, stores last element of each block
};

// Shared memory for parallel reduction
shared float sharedData[SECTION_SIZE];

void main() {
  // Get global and local indices
  uint globalIndex = gl_GlobalInvocationID.x;
  uint localIndex = gl_LocalInvocationID.x;
  uint blockIndex = gl_WorkGroupID.x;

  // Load data into shared memory
  if (isExclusive != 0) {
    if (globalIndex < arraySize && localIndex != 0) {
      sharedData[localIndex] = inputData[globalIndex - 1];
    } else {
      sharedData[localIndex] = 0.0f;  // First element becomes 0
    }
  } else {
    if (globalIndex < arraySize) {
      sharedData[localIndex] = inputData[globalIndex];
    } else {
      sharedData[localIndex] = 0.0f;
    }
  }
  memoryBarrierShared();
  barrier();

  // Kogge-Stone parallel scan
  for (uint stride = 1; stride < gl_WorkGroupSize.x / 2; stride *= 2) {
    float currentSum;
    if (localIndex >= stride) {
      currentSum = sharedData[localIndex] + sharedData[localIndex - stride];
    }
    memoryBarrierShared();
    barrier();

    if (localIndex >= stride) {
      sharedData[localIndex] += currentSum;
    }
    memoryBarrierShared();
    barrier();
  }

  // Store partial sums and block sums
  if (globalIndex < arraySize) {
    outputData[globalIndex] = sharedData[localIndex];
    // Last thread in block stores sum for block-level scan
    if (localIndex == gl_WorkGroupSize.x - 1) {
      partialSums[blockIndex] = sharedData[localIndex];
    }
  }
}
