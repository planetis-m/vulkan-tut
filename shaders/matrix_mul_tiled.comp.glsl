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

layout(constant_id = 0) const uint TILE_SIZE = 16;

shared float sharedA[TILE_SIZE * TILE_SIZE];
shared float sharedB[TILE_SIZE * TILE_SIZE];

void main() {
  uint localRow = gl_LocalInvocationID.x;
  uint localCol = gl_LocalInvocationID.y;
  uint globalRow = gl_WorkGroupID.x * gl_WorkGroupSize.x + localRow;
  uint globalCol = gl_WorkGroupID.y * gl_WorkGroupSize.y + localCol;

  float sum = 0.0;

  for (uint tileIndex = 0; tileIndex < (K + TILE_SIZE - 1) / TILE_SIZE; tileIndex++) {
    // Load tiles into shared memory
    if (globalRow < M && (tileIndex * TILE_SIZE + localCol) < K) {
      sharedA[localRow * TILE_SIZE + localCol] = A[globalRow * K + tileIndex * TILE_SIZE + localCol];
    } else {
      sharedA[localRow * TILE_SIZE + localCol] = 0.0;
    }

    if (globalCol < N && (tileIndex * TILE_SIZE + localRow) < K) {
      sharedB[localCol * TILE_SIZE + localRow] = B[(tileIndex * TILE_SIZE + localRow) * N + globalCol];
    } else {
      sharedB[localCol * TILE_SIZE + localRow] = 0.0;
    }

    // Wait for both tiles to be loaded before doing computation
    barrier();

    // Compute the partial product for this tile
    for (uint j = 0; j < TILE_SIZE; j += 4) {
      vec4 tmpA = vec4(sharedA[localRow * TILE_SIZE + j], sharedA[localRow * TILE_SIZE + j+1], sharedA[localRow * TILE_SIZE + j+2], sharedA[localRow * TILE_SIZE + j+3]);
      vec4 tmpB = vec4(sharedB[localCol * TILE_SIZE + j], sharedB[localCol * TILE_SIZE + j+1], sharedB[localCol * TILE_SIZE + j+2], sharedB[localCol * TILE_SIZE + j+3]);
      //sum += dot(tmpA, tmpB);
      sum += tmpA.x * tmpB.x;
      sum += tmpA.y * tmpB.y;
      sum += tmpA.z * tmpB.z;
      sum += tmpA.w * tmpB.w;
    }

    // Wait for all threads to finish using current tiles before loading new tiles
    barrier();
  }

  if (globalRow < M && globalCol < N) {
    C[globalRow * N + globalCol] = sum;
  }
}