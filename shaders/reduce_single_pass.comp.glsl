#version 450

#ifndef BOUNDS_CHECK
#define BOUNDS_CHECK 0
#endif

layout(local_size_x_id = 0) in;

layout(constant_id = 0) const uint SHARED_SIZE = 32;
shared int sharedData[SHARED_SIZE];
shared uint blockID;

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

layout(std430, binding = 3) buffer ControlBuffer {
  uint globalID;
  uint groupStatus[];
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;

  // Dynamic block numbering
  if (localIdx == 0) {
    blockID = atomicAdd(globalID, 1);
  }
  memoryBarrierShared();
  barrier();

  uint groupIdx = blockID;
  uint localSize = gl_WorkGroupSize.x;
  uint globalIdx = blockID * localSize * 2 * coerseFactor + localIdx;

  int sum = 0;
  uint baseIdx = globalIdx;

  for (uint tile = 0; tile < coerseFactor; tile++) {
#if !BOUNDS_CHECK
    sum += inputData[baseIdx] + inputData[baseIdx + localSize];
#else
    sum += inputData[baseIdx] +
      ((baseIdx + localSize < arraySize) ? inputData[baseIdx + localSize] : 0);
#endif
    baseIdx += 2 * localSize;
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
    if (groupIdx > 0) {
      while (atomicLoad(groupStatus[blockID - 1]) == 0) {
        // Active wait until the previous group signals completion
      }
    }
    int previous = (groupIdx > 0) ? outputData[groupIdx - 1] : 0;
    outputData[groupIdx] = sharedData[0] + previous;
    atomicStore(groupStatus[blockID], 1); // Signal completion
  }
}