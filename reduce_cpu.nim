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

# Example reduction shader
var
  inputData: array[16, float32] = [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0,
    9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0
  ]
  outputData: array[4, float32]

const localSize = 4
var sharedData: array[localSize, float32]

proc reductionShader() =
  let localIdx = gl_LocalInvocationID.x
  let localSize = gl_WorkGroupSize.x
  let globalIdx = gl_WorkGroupID.x * localSize * 2 + localIdx

  sharedData[localIdx] = inputData[globalIdx] + inputData[globalIdx + localSize]
  # barrier simulation (not needed in single-threaded CPU simulation)

  var stride = localSize div 2
  while stride > 0:
    if localIdx < stride:
      sharedData[localIdx] += sharedData[localIdx + stride]
    # barrier simulation (not needed in single-threaded CPU simulation)
    stride = stride div 2

  if localIdx == 0:
    outputData[gl_WorkGroupID.x] = sharedData[0]

# proc reductionShader() =
#   # Perform a simple reduction: sum all elements
#   let globalID = gl_GlobalInvocationID.x
#   if globalID < data.len.uint32:
#     result += data[globalID]

# Set the number of work groups and the size of each work group
let numWorkGroups = uvec3(4, 1, 1)
let workGroupSize = uvec3(localSize, 1, 1)

# Run the compute shader on CPU
runComputeOnCpu(reductionShader, numWorkGroups, workGroupSize)

var result: float32 = 0
for x in outputData:
  result += x

echo "Reduction result: ", result
