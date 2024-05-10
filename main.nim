# Example from: https://github.com/hudiyu123/Vulkan-Mandelbrot-Generator
import std/[strutils, os], mandelbrot, qoi

proc main(params: seq[string]) =
  if params.len != 2:
    quit("Two parameters required.")
  try:
    let width = params[0].parseInt
    let height = params[1].parseInt
    var x = newMandelbrotGenerator(width.int32, height.int32)
    let rawImage = x.generate()
    writeQoi("mandelbrot.qoi", rawImage, width, height)
  except:
    quit("unknown exception: " & getCurrentExceptionMsg())

when isMainModule:
  main(params = commandLineParams())
