import opengl, glut, glerrors, glhelpers, glshaderc, std/[strformat, times, math]

const
  WorkGroupSize = 256
  NumElements = 1048576
  NumWorkGroups = NumElements div WorkGroupSize

type
  PrefixSum = object
    scanProgram: GLuint
    addProgram: GLuint
    inputBuffer: GLuint
    outputBuffer: GLuint
    uniformBuffer: GLuint

  ScanParamsBuffer = object
    arraySize: GLuint
    isExclusive: GLuint
    padding: array[2, GLuint]

proc cleanup(x: PrefixSum) =
  glDeleteBuffers(1, addr x.inputBuffer)
  glDeleteBuffers(1, addr x.outputBuffer)
  glDeleteBuffers(1, addr x.uniformBuffer)
  glDeleteProgram(x.scanProgram)
  glDeleteProgram(x.addProgram)

proc initOpenGLContext() =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

proc initResources(): PrefixSum =
  # Create and compile the compute shader
  let scanShaderCode = readFile("shaders/kogge_stone_scan.comp.glsl")
  result.scanProgram = createComputeProgram(scanShaderCode, "prefix_scan.comp",
      {0.GLuint: WorkGroupSize.GLuint})
  let addShaderCode = readFile("shaders/scan_add.comp.glsl")
  result.addProgram = createComputeProgram(addShaderCode, "prefix_scan_add.comp",
      {0.GLuint: WorkGroupSize.GLuint})
  # Input buffer
  result.inputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(float32), nil, GL_STATIC_DRAW)
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, result.inputBuffer)
  let inputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_WRITE_ONLY))
  for i in 0..<NumElements:
    inputDataPtr[i] = float32(i)
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # Output buffer
  result.outputBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, NumElements*sizeof(float32), nil, GL_STATIC_DRAW)
  # Uniform buffer
  result.uniformBuffer = createGPUBuffer(GL_UNIFORM_BUFFER, sizeof(ScanParamsBuffer), nil, GL_DYNAMIC_DRAW)

proc dispatchPrefixSum(resources: PrefixSum;
    inputBuffer, outputBuffer, partialSumsBuffer, numWorkGroups: GLuint) =
  # Use the program
  glUseProgram(resources.scanProgram)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, inputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, outputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, partialSumsBuffer)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  profile("Prefix scan shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(numWorkGroups, 1, 1)
    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc dispatchAdd(resources: PrefixSum;
    outputBuffer, partialSumsBuffer, numWorkGroups: GLuint) =
  # Use the program
  glUseProgram(resources.addProgram)
  # Bind the shader storage buffers
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, outputBuffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, partialSumsBuffer)
  glBindBufferBase(GL_UNIFORM_BUFFER, 3, resources.uniformBuffer)
  profile("Add shader dispatch"):
    # Dispatch the compute shader
    glDispatchCompute(numWorkGroups, 1, 1)
    # Ensure all work is done
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc performScan(resources: var PrefixSum, inputBuffer, outputBuffer, numElements: GLuint) =
  # Calculate NumWorkgroups using ceilDiv
  let numWorkGroups = ceilDiv(numElements, WorkgroupSize).GLuint
  # PartialSums buffer
  let partialSumsBuffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, numWorkGroups.int*sizeof(float32), nil, GL_STATIC_DRAW)
  # Uniform buffer
  let uniform = ScanParamsBuffer(arraySize: numElements.uint32, isExclusive: 0)
  glNamedBufferSubData(resources.uniformBuffer, 0, sizeof(uniform), addr uniform)
  dispatchPrefixSum(resources, inputBuffer, outputBuffer, partialSumsBuffer, numWorkGroups)
  if numWorkGroups > 1:
    # Scan partial sums
    performScan(resources, partialSumsBuffer, partialSumsBuffer, numWorkGroups)
    # Add scanned sums
    let uniform = ScanParamsBuffer(arraySize: numElements.uint32, isExclusive: 0)
    glNamedBufferSubData(resources.uniformBuffer, 0, sizeof(uniform), addr uniform)
    dispatchAdd(resources, outputBuffer, partialSumsBuffer, numElements)
  glDeleteBuffers(1, addr partialSumsBuffer)

proc readResults(resources: PrefixSum): float32 =
  # Read back the results
  result = 0
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.outputBuffer)
  let outputDataPtr = cast[ptr UncheckedArray[float32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  result = outputDataPtr[NumElements-1]
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)

proc main() =
  var resources: PrefixSum
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    performScan(resources, resources.inputBuffer, resources.outputBuffer, NumElements)
    let result = readResults(resources)
    let duration = cpuTime() - start
    echo "Final prefix sum result: ", result
    echo &"Total CPU runtime: {duration*1_000:.4f} ms"
  finally:
    cleanup(resources)

main()
