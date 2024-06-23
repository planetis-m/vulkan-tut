# Compile with at least `-d:ThreadPoolSize=workgroupSizeX*workgroupSizeY*workgroupSizeZ+1`

## ## Description
##
## `runComputeOnCpu` is a template that simulates a GPU-like compute environment on the CPU.
## It organizes work into workgroups and invocations, similar to how compute shaders operate
## on GPUs.
##
## ## Parameters
##
## - `numWorkGroups: UVec3` The number of workgroups in each dimension (x, y, z).
## - `workGroupSize: UVec3` The size of each workgroup in each dimension (x, y, z).
## - `smem: untyped` Defines the shared memory for each workgroup.
## - `compute: untyped` A call to a compute shader function.
##
## ## Compute Function Signature
##
## The function called in the `compute` parameter should have the following signature:
##
## ```nim
## proc computeFunction(env: GlEnvironment, barrier: BarrierHandle,
##                      buffers: Locker[YourBufferType],
##                      shared: ptr YourSharedMemoryType,
##                      #[ ...additional parameters ]#) {.gcsafe.}
## ```
##
## ## Example
##
## ```nim
## proc myComputeShader(env: GlEnvironment, barrier: BarrierHandle,
##                      buffers: Locker[tuple[input, output: seq[float32]]],
##                      shared: ptr seq[float32], factor: float32) {.gcsafe.} =
##   # Computation logic here
##
## let numWorkGroups = uvec3(4, 4, 1)
## let workGroupSize = uvec3(256, 1, 1)
## var buffers = initLocker((input: newSeq[float32](4096), output: newSeq[float32](4096)))
##
## runComputeOnCpu(numWorkGroups, workGroupSize, newSeq[float32](256)):
##   myComputeShader(env, barrier.getHandle(), buffers, addr shared, 2.0f)
## ```

import threading/barrier, malebolgia

type
  UVec3* = object
    x, y, z: uint

  GlEnvironment* = object
    gl_GlobalInvocationID*: UVec3
    gl_WorkGroupSize*: UVec3
    gl_WorkGroupID*: UVec3
    gl_NumWorkGroups*: UVec3
    gl_LocalInvocationID*: UVec3

  BarrierHandle* = object
    x: ptr Barrier

proc uvec3*(x, y, z: uint): UVec3 =
  result = UVec3(x: x, y: y, z: z)

proc x*(v: UVec3): uint {.inline.} = v.x
proc y*(v: UVec3): uint {.inline.} = v.y
proc z*(v: UVec3): uint {.inline.} = v.z

proc getHandle*(b: var Barrier): BarrierHandle {.inline.} =
  result = BarrierHandle(x: addr(b))

proc wait*(m: BarrierHandle) {.inline.} =
  wait(m.x[])

template runComputeOnCpu*(numWorkGroups, workGroupSize: UVec3; smem, compute: untyped) =
  var env {.inject.}: GlEnvironment
  env.gl_NumWorkGroups = numWorkGroups
  env.gl_WorkGroupSize = workGroupSize

  for wgZ in 0 ..< numWorkGroups.z:
    for wgY in 0 ..< numWorkGroups.y:
      for wgX in 0 ..< numWorkGroups.x:
        env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
        # echo "New workgroup! id ", wgX, ", ", wgY
        var shared {.inject.} = smem

        var barrier {.inject.} = createBarrier(workGroupSize.x * workGroupSize.y * workGroupSize.z)
        var master = createMaster(activeProducer = true)
        master.awaitAll:
          for z in 0 ..< workGroupSize.z:
            for y in 0 ..< workGroupSize.y:
              for x in 0 ..< workGroupSize.x:
                env.gl_LocalInvocationID = uvec3(x, y, z)
                env.gl_GlobalInvocationID = uvec3(
                  wgX * workGroupSize.x + x,
                  wgY * workGroupSize.y + y,
                  wgZ * workGroupSize.z + z
                )
                master.spawn compute
