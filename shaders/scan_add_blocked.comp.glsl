#version 430

#ifndef BOUNDS_CHECK
#define BOUNDS_CHECK 0
#endif

layout(local_size_x_id = 0) in;

layout(std140, binding = 3) uniform ScanParams {
  uint arraySize;
  uint coerseFactor;
  uint isExclusive;
};

layout(std430, binding = 1) buffer OutputBuffer {
  float outputData[];
};

layout(std430, binding = 2) buffer PartialSums {
  float partialSums[];
};

void main() {
  uint localIndex = gl_LocalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x
  uint groupIndex = gl_WorkGroupID.x;
  uint globalIndex = groupIndex * localSize * coerseFactor + localIndex;

  if (groupIndex > 0) {
    float partialSum = partialSums[isExclusive != 0u ? groupIndex : groupIndex - 1];
    for (uint tile = 0; tile < coerseFactor; tile++) {
#if !BOUNDS_CHECK
      outputData[globalIndex] += partialSum;
#else
      if (globalIndex < arraySize) {
        outputData[globalIndex] += partialSum;
      }
#endif
      globalIndex += localSize;
    }
  }
}
