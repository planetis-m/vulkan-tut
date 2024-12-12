# Compile with at least `-d:ThreadPoolSize=workgroupSize+1` and
# `-d:danger --opt:none --panics:on --threads:on --tlsEmulation:off --mm:arc -d:useMalloc -g`
# ...and debug with nim-gdb or lldb

import emulate_device_exp, std/[atomics, math], malebolgia

type
  Buffers = object
    input, output: seq[int32]
    status: seq[Atomic[uint32]]
    globalCount: Atomic[uint]

  Shared = object
    buffer: seq[int32]
    localCount: uint

  Args = tuple
    n: uint
    coarseFactor: uint

proc reductionShader(env: GlEnvironment, barrier: BarrierHandle,
                     b: ptr Buffers, smem: ptr Shared, args: Args) =
  let (n, coarseFactor) = args
  # Dynamic block numbering
  let localIdx = env.gl_LocalInvocationID.x
  if localIdx == 0:
    smem.localCount = fetchAdd(b.globalCount, 1)
  wait barrier

  let groupIdx = smem.localCount
  let localSize = env.gl_WorkGroupSize.x
  var globalIdx = groupIdx * localSize * 2 * coarseFactor + localIdx

  var sum: int32 = 0
  for tile in 0 ..< coarseFactor:
    # echo "ThreadId ", localIdx, " indices: ", globalIdx, " + ", globalIdx + localSize
    sum += b.input[globalIdx] +
      (if globalIdx + localSize < n: b.input[globalIdx + localSize] else: 0)
    globalIdx += 2 * localSize
  smem.buffer[localIdx] = sum

  wait barrier
  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      # echo "Final reduction ", localIdx, " + ", localIdx + stride
      smem.buffer[localIdx] += smem.buffer[localIdx + stride]
    wait barrier # was memoryBarrierShared();barrier();
    stride = stride div 2

  if localIdx == 0:
    # Active wait until the previous group signals completion
    while load(b.status[groupIdx]) == 0: discard
    let previous = b.output[groupIdx]
    b.output[groupIdx + 1] = smem.buffer[0] + previous
    fence() # Memory fence
    store(b.status[groupIdx + 1], 1) # Mark this group as complete

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

  var buffers = Buffers(
    input: ensureMove(inputData),
    output: newSeq[int32](numWorkGroups.x + 1),
    status: newSeq[Atomic[uint32]](numWorkGroups.x + 1),
    globalCount: default(Atomic[uint])
  )

  buffers.status[0].store(1) # Set first group as ready

  # Run the compute shader on CPU, pass buffers as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, reductionShader,
    addr buffers, Shared(buffer: newSeq[int32](workGroupSize.x), localCount: 0),
    (numElements, coarseFactor))

  let result = buffers.output[^1]
  let expected = (numElements - 1)*numElements div 2
  echo "Reduction result: ", result, ", expected: ", expected

main()
