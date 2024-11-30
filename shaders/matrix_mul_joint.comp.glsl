#version 460

layout(local_size_x_id = 0) in;

layout(binding = 0) buffer ABuffer {
  float A[];
};

layout(binding = 1) buffer BBuffer {
  float B[];
};

layout(binding = 2) buffer CBuffer {
  float C[];
};

layout(binding = 3) uniform Parameters {
  int M;
  int K;
  int N;
};

layout(constant_id = 0) const uint TILE_SIZE_A = 64;
layout(constant_id = 1) const uint TILE_SIZE_B = 16;
const uint TILE_SIZE_RATIO = (TILE_SIZE_A / TILE_SIZE_B);

shared float sharedB[TILE_SIZE_RATIO * TILE_SIZE_B];

void main() {
  uint localID = gl_LocalInvocationID.x;
  uint row = gl_WorkGroupID.x * gl_WorkGroupSize.x + localID;
  uint col = gl_WorkGroupID.y * TILE_SIZE_B;

  float cReg[TILE_SIZE_B];
  for (uint i = 0; i < TILE_SIZE_B; i++) {
    cReg[i] = 0.0;
  }

  for (uint tileIndex = 0; tileIndex < (K + TILE_SIZE_RATIO - 1) / TILE_SIZE_RATIO; tileIndex++) {
    // Load tile into shared memory
    const uint i = localID / TILE_SIZE_B;
    const uint j = localID % TILE_SIZE_B;
    if (col + j < N && (tileIndex * TILE_SIZE_RATIO + i) < K) {
      sharedB[i * TILE_SIZE_B + j] = B[(tileIndex * TILE_SIZE_RATIO + i) * N + col + j];
    } else {
      sharedB[i * TILE_SIZE_B + j] = 0.0;
    }
    // Wait for the tile to be loaded before doing computation
    memoryBarrierShared();
    barrier();

    for (uint i = 0; i < TILE_SIZE_RATIO; i++) {
      // Load tile of matrix A into register
      float aReg = 0.0;
      if (row < M && (tileIndex * TILE_SIZE_RATIO + i) < K) {
        aReg = A[row * K + (tileIndex * TILE_SIZE_RATIO + i)];
      }
      // Loop over and update the output elements
      for (uint j = 0; j < TILE_SIZE_B; j++) {
        cReg[j] += aReg * sharedB[i * TILE_SIZE_B + j];
      }
    }
    // Wait for all threads to finish using current tiles before loading new tiles
    memoryBarrierShared();
    barrier();
  }

  // Store the output array variable to P elements
  for (uint j = 0; j < TILE_SIZE_B; j++) {
    if (row < M && col + j < N) {
      C[row * N + col + j] = cReg[j];
    }
  }
}
