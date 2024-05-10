import chroma, std/paths

proc c_free*(p: pointer) {.importc: "free", header: "<stdlib.h>".}

const dir = currentSourcePath().Path.parentDir
{.passc: "-I" & dir.string.}

type
  QoiDesc {.importc: "qoi_desc", header: "qoi.h", byref.} = object
    width, height: uint32
    channels: byte
    colorspace: byte

{.push callconv: cdecl, header: "qoi.h", sideEffect.}

proc qoiWrite(filename: cstring, data: pointer, desc: QoiDesc): int32 {.importc: "qoi_write".}
proc qoiRead(filename: cstring, desc: out QoiDesc, channels: int32): pointer {.importc: "qoi_read".}

{.pop.}

type
  Colorspace* = enum
    sRBG = 0
    Linear = 1

  Qoi* = object
    ## Raw QOI image data.
    width*, height*, channels*: int
    colorspace*: Colorspace
    data*: seq[ColorRGBA]

proc writeQoi*(filename: string; data: seq[ColorRGBA]; width, height: Positive) =
  let desc = QoiDesc(width: width.uint32, height: height.uint32, channels: 4, colorspace: sRBG.byte)
  if qoiWrite(filename.cstring, data[0].addr, desc) == 0:
    raise newException(ValueError, "Failed to write QOI file")

proc readQoi*(filename: string): Qoi =
  var desc: QoiDesc
  let dataPtr = qoiRead(filename.cstring, desc, 4)
  if dataPtr == nil:
    raise newException(ValueError, "Failed to read QOI file")
  var data = newSeq[ColorRGBA](desc.width*desc.height)
  copyMem(data[0].addr, dataPtr, data.len)
  c_free(dataPtr)
  result = Qoi(
    data: data,
    width: desc.width.int, height: desc.height.int, channels: desc.channels.int,
    colorspace: desc.colorspace.Colorspace
  )
