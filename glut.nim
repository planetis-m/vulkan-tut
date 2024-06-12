when defined(windows):
  const
    dllname = "(freeglut.dll|glut32.dll)"
elif defined(macosx):
  const
    dllname = "/System/Library/Frameworks/GLUT.framework/GLUT"
else:
  const
    dllname = "libglut.so.3"

const
  GLUT_API_VERSION* = 3
  GLUT_XLIB_IMPLEMENTATION* = 12 # Display mode bit masks.
  GLUT_RGB* = 0
  GLUT_RGBA* = GLUT_RGB
  GLUT_INDEX* = 1
  GLUT_SINGLE* = 0
  GLUT_DOUBLE* = 2
  GLUT_ACCUM* = 4
  GLUT_ALPHA* = 8
  GLUT_DEPTH* = 16
  GLUT_STENCIL* = 32
  GLUT_MULTISAMPLE* = 128
  GLUT_STEREO* = 256
  GLUT_LUMINANCE* = 512       # Mouse buttons.

{.push dynlib: dllname, importc.}

proc glutInit*(argcp: ptr cint, argv: pointer)
proc glutInitDisplayMode*(mode: int16)
proc glutInitDisplayString*(str: cstring)
proc glutInitWindowPosition*(x, y: int)
proc glutInitWindowSize*(width, height: int)
proc glutCreateWindow*(title: cstring): int
proc glutCreateSubWindow*(win, x, y, width, height: int): int
proc glutDestroyWindow*(win: int)
proc glutPostRedisplay*()
proc glutPostWindowRedisplay*(win: int)
proc glutSwapBuffers*()
proc glutSetWindow*(win: int)
proc glutSetWindowTitle*(title: cstring)
proc glutSetIconTitle*(title: cstring)
proc glutPositionWindow*(x, y: int)
proc glutReshapeWindow*(width, height: int)
proc glutPopWindow*()
proc glutPushWindow*()
proc glutIconifyWindow*()
proc glutShowWindow*()
proc glutHideWindow*()
proc glutFullScreen*()
proc glutSetCursor*(cursor: int)
proc glutWarpPointer*(x, y: int)
  # GLUT debugging sub-API.
proc glutReportErrors*()
{.pop.} # dynlib: dllname, importc

# Convenience procs
proc glutInit*() =
  ## version that passes `argc` and `argc` implicitely.
  var
    cmdLine {.importc: "cmdLine".}: array[0..255, cstring]
    cmdCount {.importc: "cmdCount".}: cint
  glutInit(addr(cmdCount), addr(cmdLine))
