import opengl, opengl/glut
import std/[math, strutils, os, sequtils]

const
  shaderCode = """
#version 460

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

shared float sharedData[256];

layout(binding = 0) buffer InputBuffer {
  float inputData[];
};

layout(binding = 1) buffer OutputBuffer {
  float outputData[];
};

void main() {
  uint localIdx = gl_LocalInvocationID.x;
  uint globalIdx = gl_GlobalInvocationID.x;
  uint localSize = gl_WorkGroupSize.x;

  uint stride = localSize / 2;
  sharedData[localIdx] = inputData[globalIdx] + inputData[globalIdx + stride];
  barrier();

  stride >>= 1;
  for (; stride > 0; stride >>= 1) {
    if (localIdx < stride) {
      sharedData[localIdx] += sharedData[localIdx + stride];
    }
    barrier();
  }

  if (localIdx == 0) {
    outputData[gl_WorkGroupID.x] = sharedData[0];
  }
}
"""

proc checkShaderCompilation(shader: GLuint) =
  var status: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr status)
  if status == GL_FALSE.Glint:
    var length: GLint
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, addr length)
    var infoLog = newString(length)
    glGetShaderInfoLog(shader, length, nil, infoLog.cstring)
    quit "Shader compilation error: " & infoLog

proc checkProgramLinking(program: GLuint) =
  var status: GLint
  glGetProgramiv(program, GL_LINK_STATUS, addr status)
  if status == GL_FALSE.Glint:
    var length: GLint
    glGetShaderiv(program, GL_INFO_LOG_LENGTH, addr length)
    var infoLog = newString(length)
    glGetProgramInfoLog(program, length, nil, infoLog.cstring)
    quit "Program linking error: " & infoLog

proc main() =
  # Create an OpenGL context and window
  var argc: int32 = 0
  glutInit(addr argc, nil)
  glutInitDisplayMode(GLUT_DOUBLE)
  glutInitWindowSize(640, 480)
  glutInitWindowPosition(50, 50)
  discard glutCreateWindow("OpenGL Compute")

  loadExtensions()

  # Create and compile the compute shader
  let computeShader = glCreateShader(GL_COMPUTE_SHADER)
  let shaderCodeCStr = allocCStringArray([shaderCode])
  glShaderSource(computeShader, 1, shaderCodeCstr, nil)
  deallocCStringArray(shaderCodeCStr)
  glCompileShader(computeShader)
  checkShaderCompilation(computeShader)

  # Create the shader program and link the compute shader
  let program = glCreateProgram()
  glAttachShader(program, computeShader)
  glLinkProgram(program)
  checkProgramLinking(program)

  # Initialize input data
  const numElements = 1024
  const workGroupSize = 256
  const numWorkGroups = ceilDiv(numElements, workGroupSize)

  var inputData: array[numElements, float32]
  for i in 0..<numElements:
    inputData[i] = float32(i + 1)

  # Generate and bind SSBOs
  var ssbo: array[2, GLuint]
  glGenBuffers(2, addr ssbo[0])

  # Input buffer
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo[0])
  glBufferData(GL_SHADER_STORAGE_BUFFER, numElements*sizeof(float32), addr inputData[0], GL_STATIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, ssbo[0])

  # Output buffer
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo[1])
  glBufferData(GL_SHADER_STORAGE_BUFFER, numWorkGroups*sizeof(float32), nil, GL_STATIC_DRAW)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, ssbo[1])

  # Use the program and dispatch compute shader
  glUseProgram(program)
  glDispatchCompute(numWorkGroups.GLuint, 1, 1)

  # Ensure all work is done
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)

  # Read back the results
  var outputData: array[numWorkGroups, float32]
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, numWorkGroups*sizeof(float32), addr outputData[0])

  # Perform final reduction on the CPU if necessary
  var result: float32 = 0
  for i in 0 ..< numWorkGroups:
    result = result + outputData[i]

  echo("Final reduction result: ", result)

main()
