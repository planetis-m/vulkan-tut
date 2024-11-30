#version 430

layout(local_size_x_id = 0) in;
layout(constant_id = 0) const uint SECTION_SIZE = 32;

// Uniform for array size
layout(location = 0) uniform uint arraySize;

// Input buffer
layout(std430, binding = 0) buffer InputBuffer {
  float inputData[];
};

layout(std430, binding = 1) buffer OutputBuffer {
  float partialSums[];  // Size = arraySize, stores intermediate results
};

layout(std430, binding = 2) buffer BlockSumsBuffer {
  float blockSums[];    // Size = numWorkGroups, stores last element of each block
};

// Shared memory for parallel reduction
shared float sharedDataA[SECTION_SIZE];
shared float sharedDataB[SECTION_SIZE];

void main() {
  // Get global and local indices
  uint globalIndex = gl_GlobalInvocationID.x;
  uint localIndex = gl_LocalInvocationID.x;

  // Load data into shared memory
  if (globalIndex < arraySize) {
    sharedDataA[localIndex] = inputData[globalIndex];
  } else {
    sharedDataA[localIndex] = 0.0f;
  }
  memoryBarrierShared();
  barrier();

  // Double buffered Kogge-Stone parallel scan
  bool useA = true;
  for (uint stride = 1; stride < gl_WorkGroupSize.x; stride *= 2) {
    if (localIndex >= stride) {
      if (useA) {
        sharedDataB = sharedDataA[localIndex] + sharedDataA[localIndex - stride];
      } else {
        sharedDataA = sharedDataB[localIndex] + sharedDataB[localIndex - stride];
      }
    } else {
      if (useA) {
        sharedDataB[localIndex] = sharedDataA[localIndex];
      } else {
        sharedDataA[localIndex] = sharedDataB[localIndex];
      }
    }
    memoryBarrierShared();
    barrier();

    useA = !useA;
  }

  // Store partial sums and block sums
  if (globalIndex < arraySize) {
    float result = useA ? sharedDataA[localIndex] : sharedDataB[localIndex];
    partialSums[globalIndex] = result;

    // Last thread in block stores sum for block-level scan
    if (localIndex == gl_WorkGroupSize.x - 1) {
      blockSums[blockIndex] = result;
    }
  }
}
