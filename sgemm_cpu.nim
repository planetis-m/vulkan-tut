# Compile with at least `-d:ThreadPoolSize=workgroupSize*workgroupSize+1`
# https://youtu.be/QGYvbsHDPxo and https://youtu.be/jWmtNGqub8c
# https://siboehm.com/articles/22/CUDA-MMM
import emulate_device, std/[math, strutils], malebolgia, malebolgia/lockers

proc sgemmShader(env: GlEnvironment; barrier: BarrierHandle;
                 buffers: Locker[tuple[A, B, C: seq[float32]]];
                 smem: ptr tuple[sharedA, sharedB: seq[float32]];
                 alpha, beta: float32; transposeA, transposeB: bool;
                 M, K, N, tileSize: int) {.gcsafe.} =
  let localRow = env.gl_LocalInvocationID.y.int
  let localCol = env.gl_LocalInvocationID.x.int
  let globalRow = env.gl_WorkGroupID.y.int * env.gl_WorkGroupSize.y.int + localRow
  let globalCol = env.gl_WorkGroupID.x.int * env.gl_WorkGroupSize.x.int + localCol

  var sum: float32 = 0
  for tileIndex in countup(0, ceilDiv(K, tileSize)):
    # Load tiles into shared memory
    unprotected buffers as b:
      if globalRow < M and (tileIndex * tileSize + localCol) < K:
        smem.sharedA[localRow * tileSize + localCol] =
          if transposeA: b.A[(tileIndex * tileSize + localCol) * M + globalRow]
          else: b.A[globalRow * K + tileIndex * tileSize + localCol]
      else:
        smem.sharedA[localRow * tileSize + localCol] = 0
      if globalCol < N and (tileIndex * tileSize + localRow) < K:
        smem.sharedB[localRow * tileSize + localCol] =
          if transposeB: b.B[globalCol * K + tileIndex * tileSize + localRow]
          else: b.B[(tileIndex * tileSize + localRow) * N + globalCol]
      else:
        smem.sharedB[localCol * tileSize + localRow] = 0
    # Wait for both tiles to be loaded in before doing computation
    wait barrier
    # Compute the partial product for this tile
    for j in 0..<tileSize:
      sum += smem.sharedA[localRow * tileSize + j] * smem.sharedB[j * tileSize + localCol]
    # Wait for all threads to finish using current tiles before loading in new
    wait barrier

  unprotected buffers as b:
    if globalRow < M and globalCol < N:
      b.C[globalRow * N + globalCol] = alpha * sum + beta * b.C[globalRow * N + globalCol]

# Main
const
  M = 64
  K = 16
  N = 32

  localSize = 4 # workgroupSize
  alpha: float32 = 1
  beta: float32 = 0

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(N, localSize).uint, ceilDiv(M, localSize).uint, 1)
  let workGroupSize = uvec3(localSize, localSize, 1)

  # Initialize the matrices
  var A = newSeq[float32](M * K)
  var B = newSeq[float32](K * N)

  for i in 0..<M*K:
    A[i] = float32(i)
  for i in 0..<K*N:
    B[i] = float32(i)

  var buffers = initLocker (A: A, B: B, C: newSeq[float32](M * N))

  # Run the compute shader on CPU, pass buffers and dimensions as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize,
      (newSeq[float32](localSize * localSize), newSeq[float32](localSize * localSize))):
    sgemmShader(env, barrier.getHandle(), buffers, addr shared,
        alpha, beta, transposeA = true, transposeB = false, M, K, N, localSize)

  unprotected buffers as b:
    # Verify the result
    for i in 0..<M:
      for j in 0..<N:
        var expected: float32 = 0
        expected = beta * expected
        for k in 0..<K:
          expected += alpha * b.A[i + k * M] * b.B[k * N + j] # A is transposed
        assert b.C[i * N + j] == expected,
            "Mismatch at C[$1, $2]: expected $3, got $4".format(i, j, expected, b.C[i * N + j])

main()
