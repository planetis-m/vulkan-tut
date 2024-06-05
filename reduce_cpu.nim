# https://www.youtube.com/playlist?list=PLxNPSjHT5qvtYRVdNN1yDcdSl39uHV_sU
# Compile with `-d:danger --opt:none --panics:on --threads:on --threadanalysis:off --tlsEmulation:off --mm:arc -g`
# ...and debug with nim-gdb
import std/math, threading/barrier, malebolgia, malebolgia/lockers

type
  UVec3 = object
    x, y, z: uint

type
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
                     smem: ptr[seq[int32]], n: uint) {.gcsafe.} =
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  let globalIdx = env.gl_WorkGroupID.x * localSize * 2 + localIdx

  unprotected buffers as b:
    smem[localIdx] = b.input[globalIdx] + b.input[globalIdx + localSize]
  wait barrier

  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      smem[localIdx] += smem[localIdx + stride]
    wait barrier # was memoryBarrierShared
    stride = stride div 2

  if localIdx == 0:
    unprotected buffers as b:
      b.output[env.gl_WorkGroupID.x] = smem[0]

proc runComputeOnCpu(numWorkGroups: UVec3, workGroupSize: UVec3,
                     buffers: Locker[tuple[input, output: seq[int32]]], n: uint) =
  var env: GlEnvironment
  env.gl_NumWorkGroups = numWorkGroups
  env.gl_WorkGroupSize = workGroupSize

  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)

        var barrier = createBarrier(workGroupSize.x)
        var shared = newSeq[int32](workGroupSize.x)

        var m = createMaster()
        m.awaitAll:
          for z in 0 ..< workGroupSize.z:
            for y in 0 ..< workGroupSize.y:
              for x in 0 ..< workGroupSize.x:
                env.gl_LocalInvocationID = uvec3(x, y, z)
                env.gl_GlobalInvocationID = uvec3(
                  wgX * workGroupSize.x + x,
                  wgY * workGroupSize.y + y,
                  wgZ * workGroupSize.z + z
                )
                m.spawn reductionShader(env, barrier.getHandle(), buffers, addr shared, n)

# Main
const
  numElements = 64
  localSize = 4 # workgroupSize
  gridSize = numElements div (localSize * 2) # numWorkGroups

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(gridSize, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = initLocker (inputData, newSeq[int32](gridSize))

  # Run the compute shader on CPU
  runComputeOnCpu(numWorkGroups, workGroupSize, buffers, numElements)

  unprotected buffers as b:
    let result = sum(b[1])
    let expected = (numElements - 1)*numElements div 2
    echo "Reduction result: ", result, ", expected: ", expected

main()
