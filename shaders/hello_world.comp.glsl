#version 460
#extension GL_EXT_debug_printf : require

void main() {
  debugPrintfEXT("'Hello world!' (said thread: %d)\n", gl_GlobalInvocationID.x);
}
