#version 450

layout(local_size_x_id = 0) in;

layout(constant_id = 0) const uint SHARED_SIZE = 32;
#ifndef WARP_SIZE
#define WARP_SIZE 32
#endif
shared int sharedData[SHARED_SIZE];

layout(binding = 0) buffer InputBuffer {
  int inputData[];
};

layout(binding = 1) buffer OutputBuffer {
  int outputData[];
};

layout(set = 0, binding = 2) uniform UniformBlock {
  uint n;
};

void warpReduce(uint localIdx) {
  #if WARP_SIZE >= 64
  sharedData[localIdx] += sharedData[localIdx + 64];
  memoryBarrierShared();
  #endif
  #if WARP_SIZE >= 32
  sharedData[localIdx] += sharedData[localIdx + 32];
  memoryBarrierShared();
  #endif
  sharedData[localIdx] += sharedData[localIdx + 16];
  memoryBarrierShared();
  sharedData[localIdx] += sharedData[localIdx + 8];
  memoryBarrierShared();
  sharedData[localIdx] += sharedData[localIdx + 4];
  memoryBarrierShared();
  sharedData[localIdx] += sharedData[localIdx + 2];
  memoryBarrierShared();
  sharedData[localIdx] += sharedData[localIdx + 1];
  memoryBarrierShared();
}

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
  barrier();

  for (uint stride = localSize / 2; stride > WARP_SIZE; stride >>= 1) {
    if (localIdx < stride) {
      sharedData[localIdx] += sharedData[localIdx + stride];
    }
    barrier();
  }

  // Final reduction within each subgroup
  if (localIdx < WARP_SIZE) {
    warpReduce(localIdx);
  }

  if (localIdx == 0) {
    outputData[gl_WorkGroupID.x] = sharedData[0];
  }
}
