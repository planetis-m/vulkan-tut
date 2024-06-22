# https://www.youtube.com/playlist?list=PLxNPSjHT5qvtYRVdNN1yDcdSl39uHV_sU
# https://medium.com/better-programming/optimizing-parallel-reduction-in-metal-for-apple-m1-8e8677b49b01
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb
import std/math, threading/barrier, malebolgia, malebolgia/lockers

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

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     buffers: Locker[tuple[input, output: seq[int32]]],
                     smem: ptr seq[int32], n: uint) {.gcsafe.} =
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  var globalIdx = env.gl_WorkGroupID.x * localSize * 2 + localIdx

  let gridSize = localSize * 2 * env.gl_NumWorkGroups.x

  var sum: int32 = 0
  while globalIdx < n:
    # echo "ThreadId ", localIdx, " indices: ", globalIdx, " + ", globalIdx + localSize
    unprotected buffers as b:
      sum = sum + b.input[globalIdx] + b.input[globalIdx + localSize]
      b.input[globalIdx] = sum
    globalIdx = globalIdx + gridSize
  smem[localIdx] = sum

  # unprotected buffers as b:
  #   smem[localIdx] = b.input[globalIdx] + b.input[globalIdx + localSize]

  wait barrier
  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      # echo "Final reduction ", localIdx, " + ", localIdx + stride
      smem[localIdx] += smem[localIdx + stride]
    wait barrier # was memoryBarrierShared
    stride = stride div 2

  if localIdx == 0:
    unprotected buffers as b:
      b.output[env.gl_WorkGroupID.x] = smem[0]

proc runComputeOnCpu(numWorkGroups, workGroupSize: UVec3,
                     buffers: Locker[tuple[input, output: seq[int32]]], n: uint) =
  var env: GlEnvironment
  env.gl_NumWorkGroups = numWorkGroups
  env.gl_WorkGroupSize = workGroupSize

  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
        echo "New workgroup! id ", wgX
        # Declare your shared variables here.
        var shared = newSeq[int32](workGroupSize.x)

        var barrier = createBarrier(workGroupSize.x)
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
                master.spawn reductionShader(env, barrier.getHandle(), buffers, addr shared, n)

# Main
const
  numElements = 256
  elementsPerThread = 4
  localSize = 4 # workgroupSize
  gridSize = numElements div (localSize * 2 * elementsPerThread) # numWorkGroups

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(gridSize, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = initLocker (input: inputData, output: newSeq[int32](gridSize))

  # Run the compute shader on CPU, pass buffers and normals as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, buffers, numElements)

  unprotected buffers as b:
    let result = sum(b.output)
    let expected = (numElements - 1)*numElements div 2
    echo "Reduction result: ", result, ", expected: ", expected

main()
