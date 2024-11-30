#version 460

layout(local_size_x_id = 0, local_size_y_id = 0) in;

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

layout(constant_id = 0) const uint TILE_SIZE = 32;

shared float sharedA[TILE_SIZE * TILE_SIZE];
shared float sharedB[TILE_SIZE * TILE_SIZE];

void main() {
  uint localRow = gl_LocalInvocationID.y;
  uint localCol = gl_LocalInvocationID.x;
  uint globalRow = gl_WorkGroupID.y * gl_WorkGroupSize.y + localRow;
  uint globalCol = gl_WorkGroupID.x * gl_WorkGroupSize.x + localCol;

  float sum = 0.0;
  for (uint tileIndex = 0; tileIndex < (K + TILE_SIZE - 1) / TILE_SIZE; tileIndex++) {
    // Load tiles into shared memory
    if (globalRow < M && (tileIndex * TILE_SIZE + localCol) < K) {
      sharedA[localCol * TILE_SIZE + localRow] = A[globalRow * K + tileIndex * TILE_SIZE + localCol];
    } else {
      sharedA[localCol * TILE_SIZE + localRow] = 0.0;
    }

    if (globalCol < N && (tileIndex * TILE_SIZE + localRow) < K) {
      sharedB[localRow * TILE_SIZE + localCol] = B[(tileIndex * TILE_SIZE + localRow) * N + globalCol];
    } else {
      sharedB[localRow * TILE_SIZE + localCol] = 0.0;
    }

    // Wait for both tiles to be loaded before doing computation
    memoryBarrierShared();
    barrier();

    // Compute the partial product for this tile
    for (uint j = 0; j < TILE_SIZE; j++) {
      sum += sharedA[j * TILE_SIZE + localRow] * sharedB[j * TILE_SIZE + localCol];
    }

    // Wait for all threads to finish using current tiles before loading new tiles
    memoryBarrierShared();
    barrier();
  }

  if (globalRow < M && globalCol < N) {
    C[globalRow * N + globalCol] = sum;
  }
}
