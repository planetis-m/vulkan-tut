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

proc matrixMultiplyShader(env: GlEnvironment, barrier: BarrierHandle,
                          buffers: Locker[tuple[A, B, C: seq[float32]]],
                          n: uint) {.gcsafe.} =
  let localRow = env.gl_LocalInvocationID.x
  let localCol = env.gl_LocalInvocationID.y
  let globalRow = env.gl_WorkGroupID.x * env.gl_WorkGroupSize.x + localRow
  let globalCol = env.gl_WorkGroupID.y * env.gl_WorkGroupSize.y + localCol

  var sum: float32 = 0
  if globalRow < n and globalCol < n:
    for k in 0..<n:
      unprotected buffers as b:
        sum += b.A[globalRow * n + k] * b.B[k * n + globalCol]
    unprotected buffers as b:
      b.C[globalRow * n + globalCol] = sum

proc runComputeOnCpu(numWorkGroups, workGroupSize: UVec3,
                     buffers: Locker[tuple[A, B, C: seq[float32]]], n: uint) =
  var env: GlEnvironment
  env.gl_NumWorkGroups = numWorkGroups
  env.gl_WorkGroupSize = workGroupSize

  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
        # echo "New workgroup! id ", wgX, ", ", wgY
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
                master.spawn matrixMultiplyShader(env, barrier.getHandle(), buffers, n)

# Main
const
  n = 32
  localSize = 4 # workgroupSize

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(n div localSize, n div localSize, 1)
  let workGroupSize = uvec3(localSize, localSize, 1)

  # Initialize the matrices
  var A = newSeq[float32](n * n)
  var B = newSeq[float32](n * n)

  for i in 0..<n*n:
    A[i] = float32(i)
    B[i] = float32(i)

  var buffers = initLocker (A: A, B: B, C: newSeq[float32](n * n))

  # Run the compute shader on CPU, pass buffers and dimensions as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, buffers, n)

  unprotected buffers as b:
    # Verify the result
    for i in 0..<n:
      for j in 0..<n:
        var expected: float32 = 0
        for k in 0..<n:
          expected += b.A[i * n + k] * b.B[k * n + j]
        assert b.C[i * n + j] == expected,
          "Mismatch at C[$#, $#]: expected $#, got $#".format(i, j, expected, b.C[i * n + j])

main()
