# Compile with at least `-d:ThreadPoolSize=workgroupSizeX*workgroupSizeY+1`
# https://youtu.be/watch?v=jWmtNGqub8c
# https://github.com/cwpearson/nvidia-performance-tools
# https://siboehm.com/articles/22/CUDA-MMM

import emulate_device_exp, malebolgia, std/[math, strutils]

type
  Args = tuple
    M, K, N: uint
    tileSizeA, tileSizeB: uint
    tileSizeRatio: uint

proc multiplyShader(env: GlEnvironment; barrier: BarrierHandle;
                    b: ptr tuple[A, B, C: seq[float32]];
                    sharedB: ptr seq[float32]; args: Args) {.gcsafe.} =
  let (M, K, N, tileSizeA, tileSizeB, tileSizeRatio) = args
  let row = env.gl_WorkGroupID.x * env.gl_WorkGroupSize.x + env.gl_LocalInvocationID.x
  let col = env.gl_WorkGroupID.y * tileSizeB

  var cReg = newSeq[float32](tileSizeB)
  # for i in 0..<tileSizeB:
  #   cReg[i] = 0
  for tileIndex in countup(0u, ceilDiv(K, tileSizeRatio)):
    # Load tiles into shared memory
    let i = env.gl_LocalInvocationID.x div tileSizeB
    let j = env.gl_LocalInvocationID.x mod tileSizeB
    if col + j < N and (tileIndex * tileSizeRatio + i) < K:
      sharedB[i * tileSizeB + j] = b.B[(tileIndex * tileSizeRatio + i) * N + col + j]
    else:
      sharedB[i * tileSizeB + j] = 0
    # Wait for both tiles to be loaded in before doing computation
    wait barrier
    for i in 0..<tileSizeRatio:
      # Load tile of matrix A into register
      var aReg: float32 = 0
      if row < M and (tileIndex * tileSizeRatio + i) < K:
        aReg = b.A[row * K + tileIndex * tileSizeRatio + i]
      # Loop over and update the output elements
      for j in 0..<tileSizeB:
        cReg[j] += aReg * sharedB[i * tileSizeB + j]
    # Wait for all threads to finish using current tiles before loading in new
    wait barrier

  for j in 0..<tileSizeB:
    if row < M and col + j < N:
      b.C[row * N + col + j] = cReg[j]

# Main
const
  M = 64u
  K = 16u
  N = 32u

  tileSizeA = 8u
  tileSizeB = 2u
  tileSizeRatio = tileSizeA div tileSizeB

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(M, tileSizeA), ceilDiv(N, tileSizeB), 1)
  let workGroupSize = uvec3(tileSizeA, 1, 1)

  # Initialize the matrices
  var A = newSeq[float32](M * K)
  var B = newSeq[float32](K * N)

  for i in 0..<M*K:
    A[i] = float32(i)
  for i in 0..<K*N:
    B[i] = float32(i)

  var buffers = (A: ensureMove A, B: ensureMove B, C: newSeq[float32](M * N))

  # Run the compute shader on CPU, pass buffers and dimensions as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, multiplyShader,
    addr buffers, newSeq[float32](tileSizeRatio * tileSizeB),
    (M, K, N, tileSizeA, tileSizeB, tileSizeRatio))

  # Verify the result
  for i in 0..<M:
    for j in 0..<N:
      var expected: float32 = 0
      for k in 0..<K:
        expected += buffers.A[i * K + k] * buffers.B[k * N + j]
      assert buffers.C[i * N + j] == expected,
          "Mismatch at C[$1, $2]: expected $3, got $4".format(i, j, expected, buffers.C[i * N + j])

main()
