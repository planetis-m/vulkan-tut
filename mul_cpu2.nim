# Compile with at least `-d:ThreadPoolSize=workgroupSizeX*workgroupSizeY+1`
# https://youtu.be/watch?v=jWmtNGqub8c
import std/[math, strutils], threading/barrier, malebolgia, malebolgia/lockers

type
  UVec3 = object
    x, y, z: uint

  GlEnvironment* = object
    gl_GlobalInvocationID*: UVec3
    gl_WorkGroupSize*: UVec3
    gl_WorkGroupID*: UVec3
    gl_NumWorkGroups*: UVec3
    gl_LocalInvocationID*: UVec3

  BarrierHandle* = object
    x: ptr Barrier

proc uvec3(x, y, z: uint): UVec3 =
  result = UVec3(x: x, y: y, z: z)

proc getHandle*(b: var Barrier): BarrierHandle {.inline.} =
  result = BarrierHandle(x: addr(b))

proc wait*(m: BarrierHandle) {.inline.} =
  wait(m.x[])

proc multiplyShader(env: GlEnvironment; barrier: BarrierHandle;
                    buffers: Locker[tuple[A, B, C: seq[float32]]];
                    sharedB: ptr seq[float32]; M, K, N,
                    tileWidthN, tileWidthM, tileWidthRatioK: int) {.gcsafe.} =
  let localRow = env.gl_LocalInvocationID.y.int
  let localCol = env.gl_LocalInvocationID.x.int
  let globalRow = env.gl_WorkGroupID.y.int * env.gl_WorkGroupSize.y.int + localRow
  let globalCol = env.gl_WorkGroupID.x.int * env.gl_WorkGroupSize.x.int + localCol

  var cReg = newSeq[float32](tileWidthN)
  # for i in 0..<tileWidthN:
  #   cReg[i] = 0
  for tileIndex in countup(0, ceilDiv(K, tileWidthRatioK)):
    # Load tiles into shared memory
    unprotected buffers as b:
      if globalCol < N and (tileIndex * tileWidthRatioK + localCol) < K:
        sharedB[localRow * tileWidthN + localCol] = b.B[(tileIndex * tileWidthRatioK + localCol) * N + globalCol]
      else:
        sharedB[localRow * tileWidthN + localCol] = 0
    # Wait for both tiles to be loaded in before doing computation
    wait barrier
    for i in 0..<tileWidthRatioK:
      # Load tile of matrix M into register
      var aVal: float32 = 0
      unprotected buffers as b:
        if globalRow < M and (tileIndex * tileWidthRatioK + i) < K:
          aVal = b.A[globalRow * K + tileIndex * tileWidthRatioK + i]
      # Loop over and update the output elements
      for j in 0..<tileWidthN:
        if globalCol + j < N:
          cReg[j] += aVal * sharedB[i * tileWidthN + j]
    # Wait for all threads to finish using current tiles before loading in new
    wait barrier

  unprotected buffers as b:
    for j in 0..<tileWidthN:
      if globalRow < M and globalCol + j < N:
        b.C[globalRow * N + globalCol + j] = cReg[j]

proc runComputeOnCpu(numWorkGroups, workGroupSize: UVec3;
                     buffers: Locker[tuple[A, B, C: seq[float32]]]; M, K, N,
                     tileWidthN, tileWidthM, tileWidthRatioK: int) =
  var env: GlEnvironment
  env.gl_NumWorkGroups = numWorkGroups
  env.gl_WorkGroupSize = workGroupSize

  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
        # echo "New workgroup! id ", wgX, ", ", wgY
        var shared = newSeq[float32](tileWidthRatioK * tileWidthN)

        var barrier = createBarrier(workGroupSize.x * workGroupSize.y)
        var master = createMaster(activeProducer = true)
        master.awaitAll:
          for z in 0 ..< workGroupSize.z:
            for y in 0 ..< workGroupSize.y:
              for x in 0 ..< workGroupSize.x:
                env.gl_LocalInvocationID = uvec3(x, y, z)
                env.gl_GlobalInvocationID = uvec3(
                  wgX * workGroupSize.x + x,
                  wgY * workGroupSize.y + y,
                  wgZ * workGroupSize.z + z
                )
                master.spawn multiplyShader(env, barrier.getHandle(), buffers,
                                            addr shared, M, K, N,
                                            tileWidthN, tileWidthM, tileWidthRatioK)

# Main
const
  M = 64
  K = 16
  N = 32

  localSizeX = 8 # workgroupSizeX
  localSizeY = 2 # workgroupSizeY
  localSizeRatio = localSizeX div localSizeY

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(N, localSizeX).uint, ceilDiv(M, localSizeY).uint, 1)
  let workGroupSize = uvec3(localSizeX, localSizeY, 1)

  # Initialize the matrices
  var A = newSeq[float32](M * K)
  var B = newSeq[float32](K * N)

  for i in 0..<M*K:
    A[i] = float32(i)
  for i in 0..<K*N:
    B[i] = float32(i)

  var buffers = initLocker (A: A, B: B, C: newSeq[float32](M * N))

  # Run the compute shader on CPU, pass buffers and dimensions as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, buffers,
                  M, K, N, localSizeX, localSizeY, localSizeRatio)

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
