#version 450

layout(local_size_x_id = 0) in;

layout(constant_id = 0) const uint SHARED_SIZE = 32;
shared int sharedData[SHARED_SIZE];

layout(std430, binding = 0) buffer InputBuffer {
  int inputData[];
};

layout(std430, binding = 1) buffer OutputBuffer {
  int outputData[];
};

layout(std140, binding = 2) uniform UniformBlock {
  uint arraySize;
  uint coerseFactor;
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x;
  uint globalIdx = gl_WorkGroupID.x * localSize * 2 * coerseFactor + localIdx;

  int sum;
  uint endIdx = globalIdx + (coerseFactor * 2 - 1) * localSize;

  if (globalIdx >= arraySize) { // All indices out of bounds
    sum = 0;
  } else if (endIdx < arraySize) { // All indices in bounds
    sum = inputData[globalIdx];
    for (uint tile = 1; tile < coerseFactor * 2; tile++) {
      sum += inputData[globalIdx + tile * localSize];
    }
  } else { // Mixed case - keep original bound check
    sum = inputData[globalIdx];
    for (uint tile = 1; tile < coerseFactor * 2; tile++) {
      uint idx = globalIdx + tile * localSize;
      if (idx < arraySize) {
        sum += inputData[idx];
      }
    }
  }
  sharedData[localIdx] = sum;
  memoryBarrierShared();
  barrier();

  for (uint stride = localSize / 2; stride > 64; stride >>= 1) {
    if (localIdx < stride) {
      sum += sharedData[localIdx + stride];
      sharedData[localIdx] = sum;
    }
    memoryBarrierShared();
    barrier();
  }

  // Final reduction within each subgroup
  if (localIdx < 64) {
    sum += sharedData[localIdx + 64];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 32];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 16];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 8];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 4];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 2];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
    sum += sharedData[localIdx + 1];
    sharedData[localIdx] = sum;
    memoryBarrierShared();
  }

  if (localIdx == 0) {
    outputData[gl_WorkGroupID.x] = sharedData[0];
  }
}
