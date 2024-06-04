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
var data: array[16, int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
var result: int = 0

proc reductionShader() =
  # Perform a simple reduction: sum all elements
  let globalID = gl_GlobalInvocationID.x
  if globalID < data.len.uint32:
    result += data[globalID]

# Set the number of work groups and the size of each work group
let numWorkGroups = uvec3(4, 1, 1)
let workGroupSize = uvec3(4, 1, 1)

# Run the compute shader on CPU
runComputeOnCpu(reductionShader, numWorkGroups, workGroupSize)

echo "Reduction result: ", result
