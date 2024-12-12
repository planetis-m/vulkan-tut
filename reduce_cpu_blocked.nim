# From Programming Massively Parallel Processors 4th edition (the blocked part)
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb

import emulate_device, std/math, malebolgia

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     b: ptr tuple[input, output: seq[int32]],
                     smem: ptr seq[int32], coarseFactor: uint) =
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  var globalIdx = env.gl_WorkGroupID.x * localSize * 2 * coarseFactor + localIdx

  var sum = b.input[globalIdx]
  for tile in 1 ..< 2 * coarseFactor:
    # echo "ThreadId ", localIdx, " index: ", globalIdx + tile * localSize
    # if globalIdx + tile.uint * localSize < n:
    sum = sum + b.input[globalIdx + tile.uint * localSize]
  smem[localIdx] = sum

  # smem[localIdx] = b.input[globalIdx] + b.input[globalIdx + localSize]

  wait barrier
  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      # echo "Final reduction ", localIdx, " + ", localIdx + stride
      smem[localIdx] += smem[localIdx + stride]
    wait barrier # was memoryBarrierShared
    stride = stride div 2

  if localIdx == 0:
    b.output[env.gl_WorkGroupID.x] = smem[0]

# Main
const
  numElements = 256u
  coarseFactor = 4u
  localSize = 4u # workgroupSize
  segment = localSize * 2 * coarseFactor

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(numElements, segment), 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = (input: ensureMove(inputData), output: newSeq[int32](numWorkGroups.x))

  # Run the compute shader on CPU, pass buffers and normals as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, reductionShader, addr buffers,
    newSeq[int32](workGroupSize.x), coarseFactor)

  let result = sum(buffers.output)
  let expected = (numElements - 1)*numElements div 2
  echo "Reduction result: ", result, ", expected: ", expected

main()
