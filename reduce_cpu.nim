# https://www.youtube.com/playlist?list=PLxNPSjHT5qvtYRVdNN1yDcdSl39uHV_sU
import std/math

type
  UVec3 = object
    x, y, z: uint32

var
  gl_GlobalInvocationID*: UVec3
  gl_WorkGroupSize*: UVec3
  gl_WorkGroupID*: UVec3
  gl_NumWorkGroups*: UVec3
  gl_LocalInvocationID*: UVec3

proc uvec3(x, y, z: uint32): UVec3 =
  result.x = x
  result.y = y
  result.z = z

proc runComputeOnCpu(computeShader: proc(), numWorkGroups: UVec3, workGroupSize: UVec3) =
  gl_NumWorkGroups = numWorkGroups
  gl_WorkGroupSize = workGroupSize
  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
        for z in 0 ..< workGroupSize.z:
          for y in 0 ..< workGroupSize.y:
            for x in 0 ..< workGroupSize.x:
              gl_LocalInvocationID = uvec3(x, y, z)
              gl_GlobalInvocationID = uvec3(
                wgX * workGroupSize.x + x,
                wgY * workGroupSize.y + y,
                wgZ * workGroupSize.z + z
              )
              computeShader()

template barrier() = discard

# Reduction shader
const
  numElements = 64
  localSize = 4 # workgroupSize
  gridSize = numElements div (localSize * 2) # numWorkGroups

var
  inputData: array[numElements, float32]
  outputData: array[gridSize, float32]

var sharedData: array[localSize, float32] # Because each workgroup runs sequentially this is correct.
let n: uint32 = numElements # was a shader uniform

proc reductionShader() =
  let localIdx = gl_LocalInvocationID.x
  let localSize = gl_WorkGroupSize.x
  let globalIdx = gl_WorkGroupID.x * localSize * 2 + localIdx

  sharedData[localIdx] = inputData[globalIdx] + inputData[globalIdx + localSize]
  barrier() # barrier simulation

  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      sharedData[localIdx] += sharedData[localIdx + stride]
    barrier()
    stride = stride div 2

  if localIdx == 0:
    outputData[gl_WorkGroupID.x] = sharedData[0]

# End of shader code

proc main =
  # Set the number of work groups and the size of each work group
  let numWorkGroups = uvec3(gridSize, 1, 1)
  let workGroupSize = uvec3(localSize, 1, 1)

  # Fill the input buffer
  for i in 0..<numElements:
    inputData[i] = float(i)

  # Run the compute shader on CPU
  runComputeOnCpu(reductionShader, numWorkGroups, workGroupSize)

  let result = sum(outputData)
  let expected: float32 = (numElements - 1)*numElements div 2
  echo "Reduction result: ", result, ", expected: ", expected
  assert result == expected

main()
