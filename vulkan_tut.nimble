# Package
version       = "0.1.0"
author        = "Antonis Geralis"
description   = "Vulkan compute example"
license       = "Public Domain"

# Dependencies
requires "nim >= 2.1.0"
requires "https://github.com/planetis-m/vulkan.git"

import std/os

task compile_shaders, "Compile GLSL shaders to SPIR-V format":
  let
    shaderDir = "shaders"
    outputDir = "build/shaders"
  mkDir(outputDir)
  for f in listFiles(shaderDir):
    if f.endsWith(".comp"):
      exec "glslc " & f & " -o " & outputDir / splitFile(f).name & ".spv"
