import
  opengl, glut, glerrors, glhelpers,
  std/[math, strutils, times, random, bitops, tables]

const
  NumElements = 1024 # 2^20
  WorkgroupSize = 32

  HalfRounds = 10 div 2
  KeySetLength = HalfRounds + 1
  Width = fastLog2(NumElements) # only 2^n elements supported

  SpirvBinary = staticRead("build/shaders/shuffle.comp.spv")

type
  KeySet = array[KeySetLength, uint32]

proc generateRandomKeys(keys: var KeySet, mask: uint32) =
  for i in 0..keys.high:
    keys[i] = rand(uint32) and mask

proc calculateChecksum(x: openarray[uint32]): uint32 =
  result = 0
  for i in 0..x.high:
    result = result + x[i]

proc calculateHistogram(x: openarray[uint32]): CountTable[uint32] =
  result = CountTable[uint32]()
  for i in 0..x.high:
    inc result, x[i]

type
  RandomShuffle = object
    program: GLuint
    buffer: GLuint
    uniform: GLuint

proc cleanup(x: RandomShuffle) =
  glDeleteBuffers(1, addr x.buffer)
  glDeleteBuffers(1, addr x.uniform)
  glDeleteProgram(x.program)

proc initOpenGLContext() =
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")
  glutHideWindow()
  doAssert glInit(), "Failed to load OpenGL"

const
  ArrayAlignment = 16 # Each element is 16-byte aligned
  ScalarAlignment = 4 # Scalars are 4-byte aligned

proc alignup(value, alignment: uint): uint {.inline.} =
  (value + alignment - 1) and not (alignment - 1)

proc alignup(p: pointer, alignment: uint): pointer {.inline.} =
  cast[pointer](alignup(cast[uint](p), alignment))

template `+!`(p: pointer; diff: uint): pointer =
  cast[pointer](cast[uint](p) + diff)

template `{}=`(p: pointer; value: uint32) =
  cast[ptr uint32](p)[] = value

proc initResources(): RandomShuffle =
  result.program = createComputeProgram(SpirvBinary, {0.GLuint: WorkGroupSize.GLuint})
  let bufferSize = NumElements*sizeof(float32)
  result.buffer = createGPUBuffer(GL_SHADER_STORAGE_BUFFER, bufferSize, nil, GL_DYNAMIC_DRAW)
  # Generate random keys
  var keySet: KeySet
  generateRandomKeys(keySet, (1 shl Width) - 1)
  let size = alignup(KeySetLength * ArrayAlignment, ScalarAlignment) + sizeof(int32).uint
  result.uniform = createGPUBuffer(GL_UNIFORM_BUFFER, size.GLsizeiptr, nil, GL_DYNAMIC_DRAW)
  glBindBuffer(GL_UNIFORM_BUFFER, result.uniform)
  var uniformPtr = glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY)
  for i in 0..keySet.high:
    uniformPtr{} = keySet[i]
    uniformPtr = uniformPtr +! ArrayAlignment
  uniformPtr = alignup(uniformPtr, ScalarAlignment)
  uniformPtr{} = Width.uint32
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)

proc dispatchComputeShader(resources: RandomShuffle) =
  glUseProgram(resources.program)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, resources.buffer)
  glBindBufferBase(GL_UNIFORM_BUFFER, 1, resources.uniform)
  glDispatchCompute(ceilDiv(NumElements, WorkgroupSize).GLuint, 1, 1)
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

proc checkResults(resources: RandomShuffle) =
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, resources.buffer)
  let bufferPtr = cast[ptr UncheckedArray[uint32]](glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY))
  # Checksum and histogram tests
  # let checksum = calculateChecksum(bufferPtr.toOpenArray(0, NumElements-1))
  let histogram = calculateHistogram(bufferPtr.toOpenArray(0, NumElements-1))
  discard glUnmapBuffer(GL_SHADER_STORAGE_BUFFER)
  # doAssert checksum == (NumElements - 1) * NumElements div 2
  doAssert histogram.len == NumElements

template ff(f: float, prec: int = 4): string =
  formatFloat(f*1000, ffDecimal, prec) # ms

proc main =
  randomize(123)
  var resources: RandomShuffle
  try:
    initOpenGLContext()
    resources = initResources()
    let start = cpuTime()
    dispatchComputeShader(resources)
    checkResults(resources)
    let duration = cpuTime() - start
    echo "Runtime: ", ff(duration), " ms"
  finally:
    cleanup(resources)

main()
