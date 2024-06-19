import std/[os, strutils]

task shaders, "Compile GLSL shaders to SPIR-V format":
  let
    shaderDir = "shaders"
    outputDir = "build/shaders"
  mkDir(outputDir)
  for f in listFiles(shaderDir):
    if f.endsWith(".glsl"):
      exec "glslc -g -fshader-stage=comp " & f & " -o " & outputDir / splitFile(f).name & ".spv"
