# https://www.youtube.com/playlist?list=PLxNPSjHT5qvtYRVdNN1yDcdSl39uHV_sU
# https://medium.com/better-programming/optimizing-parallel-reduction-in-metal-for-apple-m1-8e8677b49b01
# https://moderngpu.github.io/scan.html
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb
import emulate_device, std/math, malebolgia, malebolgia/lockers, std/atomics

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     buffers: Locker[tuple[input: seq[int32], output: Atomic[int32]]],
                     smem: ptr seq[int32], n: uint) {.gcsafe.} =
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  let gridSize = localSize * 2 * env.gl_NumWorkGroups.x
  var globalIdx = env.gl_WorkGroupID.x * localSize * 2 + localIdx

  var sum: int32 = 0
  while globalIdx < n:
    # echo "ThreadId ", localIdx, " indices: ", globalIdx, " + ", globalIdx + localSize
    unprotected buffers as b:
      sum = sum + b.input[globalIdx] + b.input[globalIdx + localSize]
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
      atomicInc b.output, smem[0]

# Main
const
  numElements = 256
  coerseFactor = 4
  localSize = 4 # workgroupSize
  segment = localSize * 2 * coerseFactor

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(numElements, segment).uint, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = initLocker (input: inputData, output: default(Atomic[int32]))

  # Run the compute shader on CPU, pass buffers and normals as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, newSeq[int32](workGroupSize.x)):
    reductionShader(env, barrier.getHandle(), buffers, addr shared, numElements)

  unprotected buffers as b:
    # let result = sum(b.output)
    let result = b.output.load(moRelaxed)
    let expected = (numElements - 1)*numElements div 2
    echo "Reduction result: ", result, ", expected: ", expected

main()
