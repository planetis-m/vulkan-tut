# Compile with at least `-d:ThreadPoolSize=workgroupSizeX*workgroupSizeY+1`
# https://youtu.be/watch?v=jWmtNGqub8c
# https://github.com/cwpearson/nvidia-performance-tools
import emulate_device, malebolgia, malebolgia/lockers, std/[math, strutils]

proc multiplyShader(env: GlEnvironment; barrier: BarrierHandle;
                    buffers: Locker[tuple[A, B, C: seq[float32]]];
                    sharedB: ptr seq[float32]; M, K, N,
                    tileSizeA, tileSizeB, tileSizeRatio: int) {.gcsafe.} =
  let i = env.gl_LocalInvocationID.x.int div tileSizeB
  let j = env.gl_LocalInvocationID.x.int mod tileSizeB
  let row = env.gl_WorkGroupID.x.int * env.gl_WorkGroupSize.x.int + env.gl_LocalInvocationID.x.int
  let col = env.gl_WorkGroupID.y.int * tileSizeB

  var cReg = newSeq[float32](tileSizeB)
  # for i in 0..<tileSizeB:
  #   cReg[i] = 0
  for tileIndex in countup(0, ceilDiv(K, tileSizeRatio)):
    # Load tiles into shared memory
    unprotected buffers as b:
      if col + j < N and (tileIndex * tileSizeRatio + i) < K:
        sharedB[i * tileSizeB + j] = b.B[(tileIndex * tileSizeRatio + i) * N + col + j]
      else:
        sharedB[i * tileSizeB + j] = 0
    # Wait for both tiles to be loaded in before doing computation
    wait barrier
    for i in 0..<tileSizeRatio:
      # Load tile of matrix A into register
      var aReg: float32 = 0
      unprotected buffers as b:
        if row < M and (tileIndex * tileSizeRatio + i) < K:
          aReg = b.A[row * K + tileIndex * tileSizeRatio + i]
      # Loop over and update the output elements
      for j in 0..<tileSizeB:
        cReg[j] += aReg * sharedB[i * tileSizeB + j]
    # Wait for all threads to finish using current tiles before loading in new
    wait barrier

  unprotected buffers as b:
    for j in 0..<tileSizeB:
      if row < M and col + j < N:
        b.C[row * N + col + j] = cReg[j]

# Main
const
  M = 64
  K = 16
  N = 32

  localSizeA = 8
  localSizeB = 2
  localSizeRatio = localSizeA div localSizeB

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(M, localSizeA).uint, ceilDiv(N, localSizeB).uint, 1)
  let workGroupSize = uvec3(localSizeA, 1, 1)

  # Initialize the matrices
  var A = newSeq[float32](M * K)
  var B = newSeq[float32](K * N)

  for i in 0..<M*K:
    A[i] = float32(i)
  for i in 0..<K*N:
    B[i] = float32(i)

  var buffers = initLocker (A: A, B: B, C: newSeq[float32](M * N))

  # Run the compute shader on CPU, pass buffers and dimensions as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, newSeq[float32](localSizeRatio * localSizeB)):
    multiplyShader(env, barrier.getHandle(), buffers, addr shared, M, K, N,
                   localSizeA, localSizeB, localSizeRatio)

  unprotected buffers as b:
    # Verify the result
    for i in 0..<M:
      for j in 0..<N:
        var expected: float32 = 0
        for k in 0..<K:
          expected += b.A[i * K + k] * b.B[k * N + j]
        assert b.C[i * N + j] == expected,
            "Mismatch at C[$1, $2]: expected $3, got $4".format(i, j, expected, b.C[i * N + j])

main()
