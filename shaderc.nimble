# Package

version     = "0.1.0"
author      = "Antonis Geralis"
description = "shaderc bindings"
license     = "MIT"
srcDir      = "src"

# Deps

requires "nim >= 2.0.0"

import std/distros

if detectOs(MacOSX):
  foreignDep "pkg-config shaderc"
elif detectOs(Linux):
  foreignDep "shaderc"
elif detectOs(Windows):
  foreignDep "vulkan-sdk"
