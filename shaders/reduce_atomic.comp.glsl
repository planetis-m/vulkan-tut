#version 450

layout(local_size_x_id = 0) in;

layout(constant_id = 0) const uint SHARED_SIZE = 32;
shared int sharedData[SHARED_SIZE];

layout(binding = 0) buffer InputBuffer {
  int inputData[];
};

layout(binding = 1) buffer OutputBuffer {
  int outputData;
};

layout(set = 0, binding = 2) uniform UniformBlock {
  uint n;
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x;
  uint globalIdx = gl_WorkGroupID.x * localSize * 2 + localIdx;
  uint gridSize = localSize * 2 * gl_NumWorkGroups.x;

  int sum = 0;
  while (globalIdx < n) {
    sum += inputData[globalIdx] + inputData[globalIdx + localSize];
    globalIdx += gridSize;
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
    atomicAdd(outputData, sharedData[0]);
  }
}
