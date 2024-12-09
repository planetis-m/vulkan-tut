# From Programming Massively Parallel Processors 4th edition (the blocked part)
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb
import emulate_device, std/math, malebolgia, malebolgia/lockers

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     buffers: Locker[tuple[input, output: seq[int32]]],
                     smem: ptr seq[int32], coarseFactor: uint) {.gcsafe.} =
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  var globalIdx = env.gl_WorkGroupID.x * localSize * 2 * coarseFactor + localIdx

  unprotected buffers as b:
    var sum = b.input[globalIdx]
  for tile in 1 ..< 2 * coarseFactor:
    # echo "ThreadId ", localIdx, " index: ", globalIdx + tile * localSize
    # if globalIdx + tile.uint * localSize < n:
    unprotected buffers as b:
      sum = sum + b.input[globalIdx + tile.uint * localSize]
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

# Main
const
  numElements = 256
  coarseFactor = 4
  localSize = 4 # workgroupSize
  segment = localSize * 2 * coarseFactor

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(numElements, segment).uint, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = initLocker (input: ensureMove(inputData), output: newSeq[int32](numWorkGroups.x))

  # Run the compute shader on CPU, pass buffers and normals as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, newSeq[int32](workGroupSize.x)):
    reductionShader(env, barrier.getHandle(), buffers, addr shared, coarseFactor)

  unprotected buffers as b:
    let result = sum(b.output)
    let expected = (numElements - 1)*numElements div 2
    echo "Reduction result: ", result, ", expected: ", expected

main()
