# Example from: https://github.com/hudiyu123/Vulkan-Mandelbrot-Generator
import std/[strutils, os], mandelbrot, bmp

proc main(params: seq[string]) =
  if params.len != 2:
    quit("Two parameters required.")
  try:
    let width = params[0].parseInt
    let height = params[1].parseInt
    var x = newMandelbrotGenerator(width.int32, height.int32)
    let rawImage = x.generate()
    writeFile "mandelbrot.bmp", encodeBmp(width, height, rawImage)
  except:
    quit("unknown exception: " & getCurrentExceptionMsg())

when isMainModule:
  main(params = commandLineParams())
