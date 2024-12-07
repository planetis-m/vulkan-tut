#version 430

layout(local_size_x_id = 0) in;

layout(std140, binding = 3) uniform ScanParams {
  uint arraySize;
  uint isExclusive;
};

layout(std430, binding = 1) buffer OutputBuffer {
  float outputData[];
};

layout(std430, binding = 2) buffer PartialSums {
  float partialSums[];
};

void main() {
  uint globalIdx = gl_GlobalInvocationID.x;
  uint groupIdx = gl_WorkGroupID.x;

  if (globalIdx < arraySize && groupIdx > 0) {
    outputData[globalIdx] += partialSums[isExclusive != 0u ? groupIdx : groupIdx - 1];
  }
}
