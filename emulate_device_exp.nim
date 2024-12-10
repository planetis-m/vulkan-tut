# Compile with at least `-d:ThreadPoolSize=MaxConcurrentWorkGroups*
# (workgroupSizeX*workgroupSizeY*workgroupSizeZ+1)`

## ## Description
##
## `runComputeOnCpu` is a function that simulates a GPU-like compute environment on the CPU.
## It organizes work into workgroups and invocations, similar to how compute shaders operate
## on GPUs.
##
## ## Warning
## Using `barrier()` within conditional branches leads to undefined behavior. The emulator is
## modeled using a single barrier that must be accessible from all threads within a workgroup.
##
## ## Parameters
##
## - `numWorkGroups: UVec3` The number of workgroups in each dimension (x, y, z).
## - `workGroupSize: UVec3` The size of each workgroup in each dimension (x, y, z).
## - `compute: ComputeProc[A, B, C]` The compute shader procedure to execute.
## - `ssbo: A` Storage buffer object(s) containing the data to process.
## - `smem: B` Shared memory for each workgroup.
## - `args: C` Additional arguments passed to the compute shader.
##
## ## Compute Function Signature
##
## The compute shader procedure should have the following signature:
##
## ```nim
## proc computeFunction[A, B, C](
##   env: GlEnvironment,
##   barrier: BarrierHandle,
##   buffers: A,     # Storage buffer (typically ptr T or Locker[T])
##   shared: ptr B,  # Shared memory
##   args: C         # Additional arguments
## ) {.nimcall.}
## ```
##
## ## Example
##
## ```nim
## type
##   Buffers = ptr tuple[input, output: seq[float32]]
##   Shared = seq[float32]
##   Args = object
##     factor: int32
##
## proc myComputeShader(
##     env: GlEnvironment,
##     barrier: BarrierHandle,
##     buffers: Buffers,
##     shared: ptr Shared,
##     args: Args) {.nimcall.} =
##   # Computation logic here
##
## let numWorkGroups = uvec3(4, 1, 1)
## let workGroupSize = uvec3(256, 1, 1)
## var buffers: tuple[input, output: seq[float32]]
## var numElements = 1024
## var coarseFactor = 4
##
## runComputeOnCpu(
##   numWorkGroups, workGroupSize,
##   myComputeShader,
##   addr buffers,
##   newSeq[float32](workGroupSize.x),
##   Args(factor: coarseFactor)
## )
## ```
##
## ## CUDA to GLSL Translation Table
##
## | CUDA Concept | GLSL Equivalent | Description |
## |--------------|-----------------|-------------|
## | `blockDim` | `gl_WorkGroupSize` | The size of a thread block (CUDA) or work group (GLSL) |
## | `gridDim` | `gl_NumWorkGroups` | The size of the grid (CUDA) or the number of work groups (GLSL) |
## | `blockIdx` | `gl_WorkGroupID` | The index of the current block (CUDA) or work group (GLSL) |
## | `threadIdx` | `gl_LocalInvocationID` | The index of the current thread within its block (CUDA) or work group (GLSL) |
## | `blockIdx * blockDim + threadIdx` | `gl_GlobalInvocationID` | The global index of the current thread (CUDA) or invocation (GLSL) |

import threading/barrier, malebolgia, std/math

type
  UVec3* = object
    x, y, z: uint = 1

  GlEnvironment* = object
    gl_GlobalInvocationID*: UVec3
    gl_WorkGroupSize*: UVec3
    gl_WorkGroupID*: UVec3
    gl_NumWorkGroups*: UVec3
    gl_LocalInvocationID*: UVec3

  BarrierHandle* = object
    x: ptr Barrier

  ComputeProc*[A, B, C] = proc(
    env: GlEnvironment,
    barrier: BarrierHandle,
    buffers: A,
    shared: ptr B,
    args: C
  ) {.nimcall.}

proc uvec3*(x, y, z: uint): UVec3 =
  result = UVec3(x: x, y: y, z: z)

proc x*(v: UVec3): uint {.inline.} = v.x
proc y*(v: UVec3): uint {.inline.} = v.y
proc z*(v: UVec3): uint {.inline.} = v.z

proc getHandle*(b: var Barrier): BarrierHandle {.inline.} =
  result = BarrierHandle(x: addr(b))

proc wait*(m: BarrierHandle) {.inline.} =
  wait(m.x[])

const
  MaxConcurrentWorkGroups {.intdefine.} = 2

proc wrapCompute[A, B, C](env: GlEnvironment, barrier: BarrierHandle,
    compute: ComputeProc[A, B, C], buffers: A, shared: ptr B, args: C) {.gcsafe.} =
  compute(env, barrier, buffers, shared, args)

proc workGroupProc[A, B, C](
    wgX, wgY, wgZ: uint,
    env: GlEnvironment,
    compute: ComputeProc[A, B, C],
    ssbo: A, smem: ptr B, args: C) {.nimcall.} =
  # Auxiliary proc for work group management
  var env = env # Shadow for modification
  env.gl_WorkGroupID = uvec3(wgX, wgY, wgZ)
  var smem = smem[] # Allocated per work group

  var barrier = createBarrier(
    env.gl_WorkGroupSize.x * env.gl_WorkGroupSize.y * env.gl_WorkGroupSize.z)
  # Create master for managing threads
  var master = createMaster(activeProducer = true)
  master.awaitAll:
    for z in 0 ..< env.gl_WorkGroupSize.z:
      for y in 0 ..< env.gl_WorkGroupSize.y:
        for x in 0 ..< env.gl_WorkGroupSize.x:
          env.gl_LocalInvocationID = uvec3(x, y, z)
          env.gl_GlobalInvocationID = uvec3(
            wgX * env.gl_WorkGroupSize.x + x,
            wgY * env.gl_WorkGroupSize.y + y,
            wgZ * env.gl_WorkGroupSize.z + z
          )
          master.spawn wrapCompute(env, barrier.getHandle(), compute, ssbo, addr smem, args)

proc runComputeOnCpu*[A, B, C](
    numWorkGroups, workGroupSize: UVec3,
    compute: ComputeProc[A, B, C],
    ssbo: A, smem: B, args: C) =
  let env = GlEnvironment(
    gl_NumWorkGroups: numWorkGroups,
    gl_WorkGroupSize: workGroupSize
  )
  let totalGroups = env.gl_NumWorkGroups.x * env.gl_NumWorkGroups.y * env.gl_NumWorkGroups.z
  let numBatches = ceilDiv(totalGroups, MaxConcurrentWorkGroups)
  var currentGroup = 0
  # Initialize workgroup coordinates
  var wgX, wgY, wgZ: uint = 0
  # Process workgroups in batches to limit concurrent execution
  for batch in 0 ..< numBatches:
    let endGroup = min(currentGroup + MaxConcurrentWorkGroups, totalGroups.int)
    # Create master for managing work groups
    var master = createMaster(activeProducer = false)
    master.awaitAll:
      while currentGroup < endGroup:
        master.spawn workGroupProc(wgX, wgY, wgZ, env, compute, ssbo, addr smem, args)
        # Increment coordinates, wrapping when needed
        inc wgX
        if wgX >= env.gl_NumWorkGroups.x:
          wgX = 0
          inc wgY
          if wgY >= env.gl_NumWorkGroups.y:
            wgY = 0
            inc wgZ
        inc currentGroup
