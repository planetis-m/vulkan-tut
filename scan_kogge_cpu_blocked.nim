# https://www.youtube.com/watch?v=1DBsJHVqgS0
# https://www.youtube.com/watch?v=DrD3eIw74RY
# https://www.youtube.com/watch?v=-eoUw8fTy2E
# https://www.youtube.com/watch?v=CcwdWP44aFE
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1`

import emulate_device, std/math, malebolgia, malebolgia/lockers

proc prefixSumShader(env: GlEnvironment, barrier: BarrierHandle,
                     buffers: Locker[tuple[input, output, partialSums: seq[int32]]],
                     smem: ptr tuple[segment, aggregate: seq[int32]],
                     n, coerseFactor, isExclusive: uint) {.gcsafe.} =
  let localSize = env.gl_WorkGroupSize.x
  let groupIdx = env.gl_WorkGroupID.x
  let localIdx = env.gl_LocalInvocationID.x
  let globalIdx = groupIdx * localSize * coerseFactor + localIdx

  # Load first element into shared memory
  if isExclusive != 0:
    if globalIdx < n and localIdx != 0:
      unprotected buffers as b:
        smem.segment[localIdx] = b.input[globalIdx - 1]
    else:
      smem.segment[localIdx] = 0
  else:
    if globalIdx < n:
      unprotected buffers as b:
        smem.segment[localIdx] = b.input[globalIdx]
    else:
      smem.segment[localIdx] = 0

  # Initialize indices for subsequent loads
  var sharedIdx = localIdx + localSize
  var inputIdx = globalIdx + localSize
  # Load remaining elements
  for tile in 1 ..< coerseFactor:
    unprotected buffers as b:
      smem.segment[sharedIdx] =
        (if inputIdx < n: b.input[inputIdx] else: 0)
    sharedIdx += localSize
    inputIdx += localSize

  # Memory barrier equivalent
  wait barrier

  # Per thread scan
  let segmentStart = coerseFactor * localIdx
  for offset in 1 ..< coerseFactor:
    smem.segment[segmentStart + offset] = smem.segment[segmentStart + offset - 1]

  # Kogge-Stone parallel scan
  var stride: uint = 1
  while stride < localSize:
    var currentSum: int32 = 0
    if localIdx >= stride:
      currentSum = smem.aggregate[localIdx] + smem.aggregate[localIdx - stride]

    wait barrier

    if localIdx >= stride:
      smem.aggregate[localIdx] = currentSum

    wait barrier
    stride *= 2

  # Store results and partial sums
  if globalIdx < n:
    if localIdx > 0:
      for offset in 1 ..< coerseFactor:
        smem.segment[segmentStart + offset] = smem.aggregate[segmentStart + offset - 1]

    unprotected buffers as b:
      b.output[globalIdx] = smem.segment[localIdx]

    # Last thread in block stores sum for block-level scan
    if localIdx == localSize - 1:
      unprotected buffers as b:
        if isExclusive != 0:
          b.partialSums[groupIdx] = smem.aggregate[localIdx] + b.input[globalIdx]
        else:
          b.partialSums[groupIdx] = smem.aggregate[localIdx]

proc addShader(env: GlEnvironment, barrier: BarrierHandle,
               buffers: Locker[tuple[input, output, partialSums: seq[int32]]],
               n, coerseFactor, isExclusive: uint) =

  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  let groupIdx = env.gl_WorkGroupID.x
  var globalIdx = groupIdx * localSize * coerseFactor + localIdx

  if groupIdx > 0:
    unprotected buffers as b:
      let partialSum = b.partialSums[
        if isExclusive != 0: groupIdx else: groupIdx - 1]
    for tile in 0 ..< coerseFactor:
      if globalIdx < n:
        unprotected buffers as b:
          b.output[globalIdx] += partialSum
      globalIdx += localSize

# Main
const
  numElements = 253
  coerseFactor = 4
  localSize = 4 # workgroupSize
  isExclusive = 0
  segment = localSize * coerseFactor

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(numElements, segment).uint, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = initLocker (
    input: ensureMove(inputData),
    output: newSeq[int32](numElements),
    partialSums: newSeq[int32](numWorkGroups.x)
  )

  # Run the compute shader on CPU, pass buffers as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize,
                  (newSeq[int32](workGroupSize.x * coerseFactor), newSeq[int32](workGroupSize.x))):
    prefixSumShader(env, barrier.getHandle(), buffers, addr shared, numElements,
                    coerseFactor, isExclusive)

  # if gridSize > 1:
  unprotected buffers as b:
    cumsum(b.partialSums)

  runComputeOnCpu(numWorkGroups, workGroupSize, 0):
    addShader(env, barrier.getHandle(), buffers, numElements, coerseFactor, isExclusive)

  unprotected buffers as b:
    let result = b.output[^1]
    let expected = (numElements - 1)*numElements div 2
    echo "Prefix sum result: ", result, ", expected: ", expected

main()
