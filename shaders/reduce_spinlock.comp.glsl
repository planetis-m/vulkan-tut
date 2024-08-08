#version 450

layout(local_size_x_id = 0) in;

layout(constant_id = 0) const uint SHARED_SIZE = 32;
shared int sharedData[SHARED_SIZE];

layout(std430, binding = 0) buffer InputBuffer {
  int inputData[];
};

layout(std430, binding = 1) buffer OutputBuffer {
  int outputData;
  uint lock;
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
  barrier();

  for (uint stride = localSize / 2; stride > 64; stride >>= 1) {
    if (localIdx < stride) {
      sum += sharedData[localIdx + stride];
      sharedData[localIdx] = sum;
    }
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

 /*
  * The use of a spinlock in this compute shader is safe and will not lead
  * to potential deadlocks or starvation issues that can arise from the
  * lack of forward-progress guarantees due to the GPU's architecture.
  *
  * In this case, only one thread per workgroup attempts to acquire the lock,
  * and we assume that the workgroup size exceeds the subgroup size. If this
  * assumption was violated, it could cause problems with thread divergence.
  * https://stackoverflow.com/a/58064256
  */
  if (localIdx == 0) {
    while (true) {
      if (atomicCompSwap(lock, 0, 1) == 0) {
        outputData += sharedData[0];
        atomicExchange(lock, 0);
        break;
      }
    }
  }
}
