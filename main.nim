# Example from: https://github.com/hudiyu123/Vulkan-Mandelbrot-Generator
import std/[strutils, os], mandelbrot, pixie/fileformats/qoi

proc main(params: seq[string]) =
  if params.len != 2:
    quit("Two parameters required.")
  try:
    let width = params[0].parseInt
    let height = params[1].parseInt
    var x = newMandelbrotGenerator(width.int32, height.int32)
    let qoi = Qoi(data: x.generate(), width: width, height: height, channels: 4)
    let data = encodeQoi(qoi)
    writeFile("mandelbrot.qoi", data)
  except:
    quit("unknown exception: " & getCurrentExceptionMsg())

when isMainModule:
  main(params = commandLineParams())
