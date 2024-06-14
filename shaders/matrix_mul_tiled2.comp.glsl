#version 460

layout(local_size_x_id = 0, local_size_y_id = 1) in;

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

layout(constant_id = 0) const uint TILE_WIDTH_M = 64;
layout(constant_id = 1) const uint TILE_WIDTH_N = 16;
const uint TILE_RATIO_K = (TILE_WIDTH_M / TILE_WIDTH_N);

shared float sharedB[TILE_RATIO_K * TILE_WIDTH_N];

void main() {
  uint localRow = gl_LocalInvocationID.x;
  uint localCol = gl_LocalInvocationID.y;
  uint globalRow = gl_WorkGroupID.x * gl_WorkGroupSize.x + localRow;
  uint globalCol = gl_WorkGroupID.y * gl_WorkGroupSize.y + localCol;

  float cReg[TILE_WIDTH_N];
  for (uint i = 0; i < TILE_WIDTH_N; ++i) {
    cReg[i] = 0.0;
  }

  for (uint tileIndex = 0; tileIndex < (K + TILE_RATIO_K - 1) / TILE_RATIO_K; tileIndex++) {
    // Load tile into shared memory
    if ((tileIndex * TILE_RATIO_K + localRow) < K) {
      sharedB[localCol * TILE_RATIO_K + localRow] = B[(tileIndex * TILE_RATIO_K + localRow) * N + globalCol];
    } else {
      sharedB[localCol * TILE_RATIO_K + localRow] = 0.0;
    }

    // Wait for the tile to be loaded before doing computation
    barrier();

    for (uint i = 0; i < TILE_RATIO_K; ++i) {
      // Load tile of matrix M into register
      float aVal = 0.0;
      if (globalRow < M && (tileIndex * TILE_RATIO_K + i) < K) {
        aVal = A[globalRow * K + (tileIndex * TILE_RATIO_K + i)];
      }

      // Loop over and update the output elements
      for (uint j = 0; j < TILE_WIDTH_N; ++j) {
        if (globalCol + j < N) {
          cReg[j] += aVal * sharedB[i * TILE_RATIO_K + j];
        }
      }
    }

    // Wait for all threads to finish using current tiles before loading new tiles
    barrier();
  }

  // Store the output array variable to P elements
  for (uint j = 0; j < TILE_WIDTH_N; ++j) {
    if (globalRow < M && globalCol + j < N) {
      C[globalRow * N + globalCol + j] = cReg[j];
    }
  }
}
