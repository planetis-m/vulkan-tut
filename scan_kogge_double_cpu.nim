# https://www.youtube.com/watch?v=1DBsJHVqgS0
# https://www.youtube.com/watch?v=DrD3eIw74RY
# https://www.youtube.com/watch?v=-eoUw8fTy2E
# https://www.youtube.com/watch?v=CcwdWP44aFE
# Compile with at least `-d:ThreadPoolSize=workgroupSize+1`

import emulate_device_pro, std/math, malebolgia

type
  Args = tuple
    n, isExclusive: uint

proc prefixSumShaderDoubleBuffered(
    env: GlEnvironment, barrier: BarrierHandle,
    b: ptr tuple[input, output, partialSums: seq[int32]],
    smem: ptr tuple[sharedA, sharedB: seq[int32]], args: Args) =
  let (n, isExclusive) = args
  let globalIdx = env.gl_GlobalInvocationID.x
  let localIdx = env.gl_LocalInvocationID.x
  let localSize = env.gl_WorkGroupSize.x
  let groupIdx = env.gl_WorkGroupID.x

  # Load data into shared memory A
  if isExclusive != 0:
    if globalIdx < n and localIdx != 0:
      smem.sharedA[localIdx] = b.input[globalIdx - 1]
    else:
      smem.sharedA[localIdx] = 0
  else:
    if globalIdx < n:
      smem.sharedA[localIdx] = b.input[globalIdx]
    else:
      smem.sharedA[localIdx] = 0

  wait barrier

  # Double buffered Kogge-Stone parallel scan
  var useA = true
  var stride: uint = 1
  while stride < localSize:
    if localIdx >= stride:
      if useA:
        smem.sharedB[localIdx] = smem.sharedA[localIdx] + smem.sharedA[localIdx - stride]
      else:
        smem.sharedA[localIdx] = smem.sharedB[localIdx] + smem.sharedB[localIdx - stride]
    else:
      if useA:
        smem.sharedB[localIdx] = smem.sharedA[localIdx]
      else:
        smem.sharedA[localIdx] = smem.sharedB[localIdx]

    wait barrier
    useA = not useA
    stride *= 2

  # Store results and partial sums
  if globalIdx < n:
    let result = if useA: smem.sharedA[localIdx] else: smem.sharedB[localIdx]

    b.output[globalIdx] = result

    # Last thread in block stores sum for block-level scan
    if localIdx == localSize - 1:
      if isExclusive != 0:
        b.partialSums[groupIdx] = result + b.input[globalIdx]
      else:
        b.partialSums[groupIdx] = result

proc addShader(env: GlEnvironment, barrier: BarrierHandle,
               b: ptr tuple[input, output, partialSums: seq[int32]],
               smem: ptr uint, args: Args) =
  let (n, isExclusive) = args
  let globalIdx = env.gl_GlobalInvocationID.x
  let groupIdx = env.gl_WorkGroupID.x

  if globalIdx < n and groupIdx > 0:
    let partialSumIdx = if isExclusive != 0: groupIdx
                        else: groupIdx - 1

    b.output[globalIdx] += b.partialSums[partialSumIdx]

# Main
const
  numElements = 256u
  localSize = 4u # workgroupSize
  isExclusive = 0u

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(ceilDiv(numElements, localSize), 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  var inputData = newSeq[int32](numElements)
  for i in 0..<numElements:
    inputData[i] = int32(i)

  var buffers = (
    input: ensureMove(inputData),
    output: newSeq[int32](numElements),
    partialSums: newSeq[int32](numWorkGroups.x) # gridSize
  )

  # Run the compute shader on CPU, pass buffers as parameters.
  runComputeOnCpu(numWorkGroups, workGroupSize, prefixSumShaderDoubleBuffered,
    addr buffers, (newSeq[int32](workGroupSize.x), newSeq[int32](workGroupSize.x)),
    (numElements, isExclusive))

  # if gridSize > 1:
  cumsum(buffers.partialSums)

  runComputeOnCpu(
    numWorkGroups, workGroupSize, addShader, addr buffers, 0, (numElements, isExclusive))

  let result = buffers.output[^1]
  let expected = (numElements - 1)*numElements div 2
  echo "Prefix sum result: ", result, ", expected: ", expected

main()
