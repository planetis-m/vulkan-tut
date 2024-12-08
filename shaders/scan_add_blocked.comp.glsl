#version 430

#ifndef BOUNDS_CHECK
#define BOUNDS_CHECK 0
#endif

layout(local_size_x_id = 0) in;

layout(std140, binding = 3) uniform ScanParams {
  uint arraySize;
  uint coarseFactor;
  uint isExclusive;
};

layout(std430, binding = 1) buffer OutputBuffer {
  float outputData[];
};

layout(std430, binding = 2) buffer PartialSums {
  float partialSums[];
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x
  uint groupIdx = gl_WorkGroupID.x;
  uint globalIdx = groupIdx * localSize * coarseFactor + localIdx;

  if (groupIdx > 0) {
    float partialSum = partialSums[isExclusive != 0u ? groupIdx : groupIdx - 1];
    for (uint tile = 0; tile < coarseFactor; tile++) {
#if !BOUNDS_CHECK
      outputData[globalIdx] += partialSum;
#else
      if (globalIdx < arraySize) {
        outputData[globalIdx] += partialSum;
      }
#endif
      globalIdx += localSize;
    }
  }
}
