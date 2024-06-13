import opengl

type
  GLError* = object of CatchableError
    errorCode*: GLenum

proc getGLErrorMessage*(errorCode: GLenum): string =
  case errorCode
  of GL_INVALID_ENUM:
    "An unacceptable value is specified for an enumerated argument."
  of GL_INVALID_VALUE:
    "A numeric argument is out of range."
  of GL_INVALID_OPERATION:
    "The specified operation is not allowed in the current state."
  of GL_INVALID_FRAMEBUFFER_OPERATION:
    "The framebuffer object is not complete."
  of GL_OUT_OF_MEMORY:
    "There is not enough memory left to execute the command."
  of GL_STACK_UNDERFLOW:
    "An attempt has been made to perform an operation that would cause an internal stack to underflow."
  of GL_STACK_OVERFLOW:
    "An attempt has been made to perform an operation that would cause an internal stack to overflow."
  of GL_CONTEXT_LOST:
    "The OpenGL context has been lost and cannot be restored."
  of GL_TABLE_TOO_LARGE:
    "The specified table exceeds the implementation's maximum supported table size."
  else:
    # assert errorCode != GL_NO_ERROR
    "Unknown OpenGL error."

proc checkGLError*() {.noinline.} =
  var errorCode = glGetError()
  if errorCode != GL_NO_ERROR:
    let errorMessage = getGLErrorMessage(errorCode)
    var exc = new(GLError)
    exc.errorCode = errorCode
    exc.msg = "OpenGL Error: " & errorMessage
    raise exc
