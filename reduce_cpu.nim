# https://www.youtube.com/playlist?list=PLxNPSjHT5qvtYRVdNN1yDcdSl39uHV_sU
# https://www.youtube.com/watch?v=voFt2e2QXtA
# https://medium.com/better-programming/optimizing-parallel-reduction-in-metal-for-apple-m1-8e8677b49b01
# https://moderngpu.github.io/scan.html
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb

import emulate_device, std/math, malebolgia

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     b: ptr tuple[input, output: seq[int32]],
                     smem: ptr seq[int32], n: uint) =

  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  let gridSize = localSize * 2 * env.gl_NumWorkGroups.x
  var globalIdx = env.gl_WorkGroupID.x * localSize * 2 + localIdx

  # Memory coalescing occurs when threads in the same subgroup access adjacent memory
  # locations simultaneously - not when a single thread accesses different locations
  # sequentially. Here, each thread reads two values with a fixed stride between them.
  var sum: int32 = 0
  while globalIdx < n:
    # echo "ThreadId ", localIdx, " indices: ", globalIdx, " + ", globalIdx + localSize
    sum += b.input[globalIdx] +
      (if globalIdx + localSize < n: b.input[globalIdx + localSize] else: 0)
    globalIdx = globalIdx + gridSize
  smem[localIdx] = sum

  # smem[localIdx] = b.input[globalIdx] + b.input[globalIdx + localSize]

  wait barrier
  var stride = localSize div 2
  while stride > 1:
    if localIdx < stride:
      # echo "Final reduction ", localIdx, " + ", localIdx + stride
      smem[localIdx] += smem[localIdx + stride]
    wait barrier # was memoryBarrierShared();barrier();
    stride = stride div 2

  # Final reduction within each subgroup
  # if localIdx < 2:
  #   smem[localIdx] += smem[localIdx + 2]
  #   fence()
  # wait barrier # on GPU threads within a subgroup execute in lock-step
  if localIdx < 1:
    smem[localIdx] += smem[localIdx + 1]
    fence()

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

  # Run the compute shader on CPU, pass buffers as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, reductionShader, addr buffers,
    newSeq[int32](workGroupSize.x), numElements)

  let result = sum(buffers.output)
  let expected = (numElements - 1)*numElements div 2
  echo "Reduction result: ", result, ", expected: ", expected

main()
