# Copyright 2018 The Shaderc Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

when defined(linux):
  const shadercDLL = "libshaderc_shared.so"
elif defined(windows):
  const shadercDLL = "shaderc_shared.dll"
elif defined(macosx):
  const shadercDLL = "libshaderc_shared.dylib"
else:
  {.error: "Shaderc integration not implemented on this platform".}

{.passL: "-lshaderc_shared".}
when defined(windows):
  {.passL: "-L$VULKAN_SDK/lib".}

# From status.h
type
  ShadercCompilationStatus* = enum
    Success = 0,
    InvalidStage ## error stage deduction
    CompilationError,
    InternalError, ## unexpected failure
    NullResultObject,
    InvalidAssembly,
    ValidationError,
    TransformationError,
    ConfigurationError

# From env.h
type ## For Vulkan, use Vulkan's mapping of version numbers to integers.
     ## See vulkan.h
  ShadercTargetEnv* {.size: sizeof(cint).} = enum
    Vulkan, ## SPIR-V under Vulkan semantics
    Opengl, ## SPIR-V under OpenGL semantics
            ## NOTE: SPIR-V code generation is not supported for shaders under OpenGL
            ## compatibility profile.
    OpenglCompat, ## SPIR-V under OpenGL semantics,
                  ## including compatibility profile
                  ## functions
    Webgpu ## Deprecated, SPIR-V under WebGPU semantics
  ShadercEnvVersion* {.size: sizeof(cint).} = enum
    Vulkan10 = ((1 shl 22)),
    Vulkan11 = ((1 shl 22) or (1 shl 12)),
    Vulkan12 = ((1 shl 22) or (2 shl 12)),
    Vulkan13 = ((1 shl 22) or (3 shl 12)), ## \
      ## For OpenGL, use the number from #version in shaders.
    Opengl45 = 450,
    Webgpu ## Deprecated, WebGPU env never defined versions

const
  shadercTargetEnvDefault* = ShadercTargetEnv.Vulkan

## The known versions of SPIR-V.

type ## Use the values used for word 1 of a SPIR-V binary:
     ## - bits 24 to 31: zero
     ## - bits 16 to 23: major version number
     ## - bits 8 to 15: minor version number
     ## - bits 0 to 7: zero
  ShadercSpirvVersion* {.size: sizeof(cint).} = enum
    Spirv10 = 0x010000,
    Spirv11 = 0x010100,
    Spirv12 = 0x010200,
    Spirv13 = 0x010300,
    Spirv14 = 0x010400,
    Spirv15 = 0x010500,
    Spirv16 = 0x010600

# From shaderc.h

type ## Forced shader kinds. These shader kinds force the compiler to compile the
     ## source code as the specified kind of shader.
  ShadercSourceLanguage* = enum
    Glsl,
    Hlsl
  ShadercShaderKind* = enum
    VertexShader,
    FragmentShader,
    ComputeShader,
    GeometryShader,
    TessControlShader,
    TessEvaluationShader,
    GlslInferFromSource, ## \
      ## Default shader kinds. Compiler will fall back to compile the source code as
      ## the specified kind of shader when #pragma annotation is not found in the
      ## source code.
    GlslDefaultVertexShader,
    GlslDefaultFragmentShader,
    GlslDefaultComputeShader,
    GlslDefaultGeometryShader,
    GlslDefaultTessControlShader,
    GlslDefaultTessEvaluationShader,
    SpirvAssembly,
    RaygenShader,
    AnyhitShader,
    ClosesthitShader,
    MissShader,
    IntersectionShader,
    CallableShader,
    GlslDefaultRaygenShader,
    GlslDefaultAnyhitShader,
    GlslDefaultClosesthitShader,
    GlslDefaultMissShader,
    GlslDefaultIntersectionShader,
    GlslDefaultCallableShader,
    TaskShader,
    MeshShader,
    GlslDefaultTaskShader,
    GlslDefaultMeshShader
  ShadercProfile* = enum
    ProfileNone, ## Used if and only if GLSL version did not specify
                 ## profiles.
    ProfileCore,
    ProfileCompatibility, ## Disabled. This generates an error
    ProfileEs

const
  GlslVertexShader* = VertexShader
  GlslFragmentShader* = FragmentShader
  GlslComputeShader* = ComputeShader
  GlslGeometryShader* = GeometryShader
  GlslTessControlShader* = TessControlShader
  GlslTessEvaluationShader* = TessEvaluationShader
  GlslRaygenShader* = RaygenShader
  GlslAnyhitShader* = AnyhitShader
  GlslClosesthitShader* = ClosesthitShader
  GlslMissShader* = MissShader
  GlslIntersectionShader* = IntersectionShader
  GlslCallableShader* = CallableShader
  GlslTaskShader* = TaskShader
  GlslMeshShader* = MeshShader

## Optimization level.

type
  ShadercOptimizationLevel* = enum
    Zero, ## no optimization
    Size, ## optimize towards reducing code size
    Performance ## optimize towards performance

## Resource limits.

type
  ShadercLimit* = enum
    MaxLights,
    MaxClipPlanes,
    MaxTextureUnits,
    MaxTextureCoords,
    MaxVertexAttribs,
    MaxVertexUniformComponents,
    MaxVaryingFloats,
    MaxVertexTextureImageUnits,
    MaxCombinedTextureImageUnits,
    MaxTextureImageUnits,
    MaxFragmentUniformComponents,
    MaxDrawBuffers,
    MaxVertexUniformVectors,
    MaxVaryingVectors,
    MaxFragmentUniformVectors,
    MaxVertexOutputVectors,
    MaxFragmentInputVectors,
    MinProgramTexelOffset,
    MaxProgramTexelOffset,
    MaxClipDistances,
    MaxComputeWorkGroupCountX,
    MaxComputeWorkGroupCountY,
    MaxComputeWorkGroupCountZ,
    MaxComputeWorkGroupSizeX,
    MaxComputeWorkGroupSizeY,
    MaxComputeWorkGroupSizeZ,
    MaxComputeUniformComponents,
    MaxComputeTextureImageUnits,
    MaxComputeImageUniforms,
    MaxComputeAtomicCounters,
    MaxComputeAtomicCounterBuffers,
    MaxVaryingComponents,
    MaxVertexOutputComponents,
    MaxGeometryInputComponents,
    MaxGeometryOutputComponents,
    MaxFragmentInputComponents,
    MaxImageUnits,
    MaxCombinedImageUnitsAndFragmentOutputs,
    MaxCombinedShaderOutputResources,
    MaxImageSamples,
    MaxVertexImageUniforms,
    MaxTessControlImageUniforms,
    MaxTessEvaluationImageUniforms,
    MaxGeometryImageUniforms,
    MaxFragmentImageUniforms,
    MaxCombinedImageUniforms,
    MaxGeometryTextureImageUnits,
    MaxGeometryOutputVertices,
    MaxGeometryTotalOutputComponents,
    MaxGeometryUniformComponents,
    MaxGeometryVaryingComponents,
    MaxTessControlInputComponents,
    MaxTessControlOutputComponents,
    MaxTessControlTextureImageUnits,
    MaxTessControlUniformComponents,
    MaxTessControlTotalOutputComponents,
    MaxTessEvaluationInputComponents,
    MaxTessEvaluationOutputComponents,
    MaxTessEvaluationTextureImageUnits,
    MaxTessEvaluationUniformComponents,
    MaxTessPatchComponents,
    MaxPatchVertices,
    MaxTessGenLevel,
    MaxViewports,
    MaxVertexAtomicCounters,
    MaxTessControlAtomicCounters,
    MaxTessEvaluationAtomicCounters,
    MaxGeometryAtomicCounters,
    MaxFragmentAtomicCounters,
    MaxCombinedAtomicCounters,
    MaxAtomicCounterBindings,
    MaxVertexAtomicCounterBuffers,
    MaxTessControlAtomicCounterBuffers,
    MaxTessEvaluationAtomicCounterBuffers,
    MaxGeometryAtomicCounterBuffers,
    MaxFragmentAtomicCounterBuffers,
    MaxCombinedAtomicCounterBuffers,
    MaxAtomicCounterBufferSize,
    MaxTransformFeedbackBuffers,
    MaxTransformFeedbackInterleavedComponents,
    MaxCullDistances,
    MaxCombinedClipAndCullDistances,
    MaxSamples,
    MaxMeshOutputVerticesNv,
    MaxMeshOutputPrimitivesNv,
    MaxMeshWorkGroupSizeXNv,
    MaxMeshWorkGroupSizeYNv,
    MaxMeshWorkGroupSizeZNv,
    MaxTaskWorkGroupSizeXNv,
    MaxTaskWorkGroupSizeYNv,
    MaxTaskWorkGroupSizeZNv,
    MaxMeshViewCountNv,
    MaxMeshOutputVerticesExt,
    MaxMeshOutputPrimitivesExt,
    MaxMeshWorkGroupSizeXExt,
    MaxMeshWorkGroupSizeYExt,
    MaxMeshWorkGroupSizeZExt,
    MaxTaskWorkGroupSizeXExt,
    MaxTaskWorkGroupSizeYExt,
    MaxTaskWorkGroupSizeZExt,
    MaxMeshViewCountExt,
    MaxDualSourceDrawBuffersExt

## Uniform resource kinds.
## In Vulkan, uniform resources are bound to the pipeline via descriptors
## with numbered bindings and sets.

type
  ShadercUniformKind* = enum
    Image, ## Image and image buffer.
    Sampler, ## Pure sampler.
    Texture, ## Sampled texture in GLSL, and Shader Resource View in HLSL.
    Buffer, ## Uniform Buffer Object (UBO) in GLSL. Cbuffer in HLSL.
    StorageBuffer, ## Shader Storage Buffer Object (SSBO) in GLSL.
    UnorderedAccessView ## \
      ## Unordered Access View, in HLSL.
      ## (Writable storage image or storage buffer.)

## Usage examples:
##
## Aggressively release compiler resources, but spend time in initialization
## for each new use.
##      shaderc_compiler_t compiler = shaderc_compiler_initialize();
##      shaderc_compilation_result_t result = shaderc_compile_into_spv(
##          compiler, "#version 450\nvoid main() {}", 27,
##          shaderc_glsl_vertex_shader, "main.vert", "main", nullptr);
##      // Do stuff with compilation results.
##      shaderc_result_release(result);
##      shaderc_compiler_release(compiler);
##
## Keep the compiler object around for a long time, but pay for extra space
## occupied.
##      shaderc_compiler_t compiler = shaderc_compiler_initialize();
##      // On the same, other or multiple simultaneous threads.
##      shaderc_compilation_result_t result = shaderc_compile_into_spv(
##          compiler, "#version 450\nvoid main() {}", 27,
##          shaderc_glsl_vertex_shader, "main.vert", "main", nullptr);
##      // Do stuff with compilation results.
##      shaderc_result_release(result);
##      // Once no more compilations are to happen.
##      shaderc_compiler_release(compiler);

type
  shadercCompiler {.nodecl, bycopy.} = object
  ShadercCompilerT* = ptr shadercCompiler ## \
    ## An opaque handle to an object that manages all compiler state.

type
  shadercCompileOptions {.nodecl, bycopy.} = object
  ShadercCompileOptionsT* = ptr shadercCompileOptions ## \
    ## An opaque handle to an object that manages options to a single compilation result.

## Source text inclusion via #include is supported with a pair of callbacks
## to an "includer" on the client side.  The first callback processes an
## inclusion request, and returns an include result.  The includer owns
## the contents of the result, and those contents must remain valid until the
## second callback is invoked to release the result.  Both callbacks take a
## user_data argument to specify the client context.
## To return an error, set the source_name to an empty string and put your
## error message in content.
## An include result.

type
  ShadercIncludeResult* {.bycopy.} = object
    sourceName*: cstring ## \
      ## The name of the source file.  The name should be fully resolved
      ## in the sense that it should be a unique name in the context of the
      ## includer.  For example, if the includer maps source names to files in
      ## a filesystem, then this name should be the absolute path of the file.
      ## For a failed inclusion, this string is empty.
    sourceNameLength*: csize_t
    content*: cstring ## \
      ## The text contents of the source file in the normal case.
      ## For a failed inclusion, this contains the error message.
    contentLength*: csize_t
    userData*: pointer ## User data to be passed along with this request.

## The kinds of include requests.

type
  ShadercIncludeType* = enum
    Relative, ## E.g. #include "source"
    Standard ## E.g. #include <source>

## An includer callback type for mapping an #include request to an include
## result.  The user_data parameter specifies the client context.  The
## requested_source parameter specifies the name of the source being requested.
## The type parameter specifies the kind of inclusion request being made.
## The requesting_source parameter specifies the name of the source containing
## the #include request.  The includer owns the result object and its contents,
## and both must remain valid until the release callback is called on the result
## object.

type
  ShadercIncludeResolveFn* = proc (userData: pointer; requestedSource: cstring;
                                   `type`: cint; requestingSource: cstring;
                                   includeDepth: csize_t): ptr ShadercIncludeResult

type
  ShadercIncludeResultReleaseFn* = proc (userData: pointer;
      includeResult: ptr ShadercIncludeResult) ## \
        ## An includer callback type for destroying an include result.

type
  shadercCompilationResult {.nodecl, bycopy.} = object
  ShadercCompilationResultT* = ptr shadercCompilationResult ## \
    ## An opaque handle to the results of a call to any shaderc_compile_into_*()
    ## function.

when defined(windows):
  {.pragma: shadercExport, codegenDecl: "__declspec(dllimport) $# $#$#".}
else:
  {.pragma: shadercExport.}

{.push callConv: cdecl, dynlib: shadercDLL.}

proc shadercCompilerInitialize*(): ShadercCompilerT {.importc: "shaderc_compiler_initialize".}
  ## Returns a shaderc_compiler_t that can be used to compile modules.
  ## A return of NULL indicates that there was an error initializing the compiler.
  ## Any function operating on shaderc_compiler_t must offer the basic
  ## thread-safety guarantee.
  ## [http://herbsutter.com/2014/01/13/gotw-95-solution-thread-safety-and-synchronization/]
  ## That is: concurrent invocation of these functions on DIFFERENT objects needs
  ## no synchronization; concurrent invocation of these functions on the SAME
  ## object requires synchronization IF AND ONLY IF some of them take a non-const
  ## argument.

proc release*(a1: ShadercCompilerT) {.importc: "shaderc_compiler_release".}
  ## Releases the resources held by the shaderc_compiler_t.
  ## After this call it is invalid to make any future calls to functions
  ## involving this shaderc_compiler_t.

proc shadercCompileOptionsInitialize*(): ShadercCompileOptionsT {.
    importc: "shaderc_compile_options_initialize".}
  ## Returns a default-initialized shaderc_compile_options_t that can be used
  ## to modify the functionality of a compiled module.
  ## A return of NULL indicates that there was an error initializing the options.
  ## Any function operating on shaderc_compile_options_t must offer the
  ## basic thread-safety guarantee.

proc clone*(options: ShadercCompileOptionsT): ShadercCompileOptionsT {.
    importc: "shaderc_compile_options_clone".}
  ## Returns a copy of the given shaderc_compile_options_t.
  ## If NULL is passed as the parameter the call is the same as
  ## shaderc_compile_options_init.

proc release*(options: ShadercCompileOptionsT) {.
    importc: "shaderc_compile_options_release".}
  ## Releases the compilation options. It is invalid to use the given
  ## shaderc_compile_options_t object in any future calls. It is safe to pass
  ## NULL to this function, and doing such will have no effect.

proc addMacroDefinition*(options: ShadercCompileOptionsT;
    name: cstring; nameLength: csize_t; value: cstring; valueLength: csize_t) {.
    importc: "shaderc_compile_options_add_macro_definition".}
  ## Adds a predefined macro to the compilation options. This has the same
  ## effect as passing -Dname=value to the command-line compiler.  If value
  ## is NULL, it has the same effect as passing -Dname to the command-line
  ## compiler. If a macro definition with the same name has previously been
  ## added, the value is replaced with the new value. The macro name and
  ## value are passed in with char pointers, which point to their data, and
  ## the lengths of their data. The strings that the name and value pointers
  ## point to must remain valid for the duration of the call, but can be
  ## modified or deleted after this function has returned. In case of adding
  ## a valueless macro, the value argument should be a null pointer or the
  ## value_length should be 0u.

proc setSourceLanguage*(options: ShadercCompileOptionsT;
    lang: ShadercSourceLanguage) {.importc: "shaderc_compile_options_set_source_language".}
  ## Sets the source language.  The default is GLSL.

proc setGenerateDebugInfo*(options: ShadercCompileOptionsT) {.
    importc: "shaderc_compile_options_set_generate_debug_info".}
  ## Sets the compiler mode to generate debug information in the output.

proc setOptimizationLevel*(options: ShadercCompileOptionsT;
    level: ShadercOptimizationLevel) {.importc: "shaderc_compile_options_set_optimization_level".}
  ## Sets the compiler optimization level to the given level. Only the last one
  ## takes effect if multiple calls of this function exist.

proc setForcedVersionProfile*(
    options: ShadercCompileOptionsT; version: cint; profile: ShadercProfile) {.
    importc: "shaderc_compile_options_set_forced_version_profile".}
  ## Forces the GLSL language version and profile to a given pair. The version
  ## number is the same as would appear in the #version annotation in the source.
  ## Version and profile specified here overrides the #version annotation in the
  ## source. Use profile: 'shaderc_profile_none' for GLSL versions that do not
  ## define profiles, e.g. versions below 150.

proc setIncludeCallbacks*(options: ShadercCompileOptionsT;
    resolver: ShadercIncludeResolveFn;
    resultReleaser: ShadercIncludeResultReleaseFn; userData: pointer) {.
    importc: "shaderc_compile_options_set_include_callbacks".}
  ## Sets includer callback functions.

proc setSuppressWarnings*(options: ShadercCompileOptionsT) {.
    importc: "shaderc_compile_options_set_suppress_warnings".}
  ## Sets the compiler mode to suppress warnings, overriding warnings-as-errors
  ## mode. When both suppress-warnings and warnings-as-errors modes are
  ## turned on, warning messages will be inhibited, and will not be emitted
  ## as error messages.

proc setTargetEnv*(options: ShadercCompileOptionsT; target: ShadercTargetEnv;
    version: uint32) {.importc: "shaderc_compile_options_set_target_env".}
  ## Sets the target shader environment, affecting which warnings or errors will
  ## be issued.  The version will be for distinguishing between different versions
  ## of the target environment.  The version value should be either 0 or
  ## a value listed in shaderc_env_version.  The 0 value maps to Vulkan 1.0 if
  ## |target| is Vulkan, and it maps to OpenGL 4.5 if |target| is OpenGL.

proc setTargetSpirv*(options: ShadercCompileOptionsT;
    version: ShadercSpirvVersion) {.importc: "shaderc_compile_options_set_target_spirv".}
  ## Sets the target SPIR-V version. The generated module will use this version
  ## of SPIR-V.  Each target environment determines what versions of SPIR-V
  ## it can consume.  Defaults to the highest version of SPIR-V 1.0 which is
  ## required to be supported by the target environment.  E.g. Default to SPIR-V
  ## 1.0 for Vulkan 1.0 and SPIR-V 1.3 for Vulkan 1.1.

proc setWarningsAsErrors*(options: ShadercCompileOptionsT) {.
    importc: "shaderc_compile_options_set_warnings_as_errors".}
  ## Sets the compiler mode to treat all warnings as errors. Note the
  ## suppress-warnings mode overrides this option, i.e. if both
  ## warning-as-errors and suppress-warnings modes are set, warnings will not
  ## be emitted as error messages.

proc setLimit*(options: ShadercCompileOptionsT; limit: ShadercLimit;
    value: cint) {.importc: "shaderc_compile_options_set_limit".}
  ## Sets a resource limit.

proc setAutoBindUniforms*(options: ShadercCompileOptionsT; autoBind: bool) {.
    importc: "shaderc_compile_options_set_auto_bind_uniforms".}
  ## Sets whether the compiler should automatically assign bindings to uniforms
  ## that aren't already explicitly bound in the shader source.

proc setAutoCombinedImageSampler*(options: ShadercCompileOptionsT; upgrade: bool) {.
    importc: "shaderc_compile_options_set_auto_combined_image_sampler".}
  ## Sets whether the compiler should automatically remove sampler variables
  ## and convert image variables to combined image-sampler variables.

proc setHlslIoMapping*(options: ShadercCompileOptionsT; hlslIomap: bool) {.
    importc: "shaderc_compile_options_set_hlsl_io_mapping".}
  ## Sets whether the compiler should use HLSL IO mapping rules for bindings.
  ## Defaults to false.

proc setHlslOffsets*(options: ShadercCompileOptionsT; hlslOffsets: bool) {.
    importc: "shaderc_compile_options_set_hlsl_offsets".}
  ## Sets whether the compiler should determine block member offsets using HLSL
  ## packing rules instead of standard GLSL rules.  Defaults to false.  Only
  ## affects GLSL compilation.  HLSL rules are always used when compiling HLSL.

proc setBindingBase*(options: ShadercCompileOptionsT; kind: ShadercUniformKind;
    base: uint32) {.importc: "shaderc_compile_options_set_binding_base".}
  ## Sets the base binding number used for for a uniform resource type when
  ## automatically assigning bindings.  For GLSL compilation, sets the lowest
  ## automatically assigned number.  For HLSL compilation, the regsiter number
  ## assigned to the resource is added to this specified base.

proc setBindingBaseForStage*(options: ShadercCompileOptionsT; shaderKind: ShadercShaderKind;
    kind: ShadercUniformKind; base: uint32) {.
    importc: "shaderc_compile_options_set_binding_base_for_stage".}
  ## Like shaderc_compile_options_set_binding_base, but only takes effect when
  ## compiling a given shader stage.  The stage is assumed to be one of vertex,
  ## fragment, tessellation evaluation, tesselation control, geometry, or compute.

proc setPreserveBindings*(options: ShadercCompileOptionsT; preserveBindings: bool) {.
    importc: "shaderc_compile_options_set_preserve_bindings".}
  ## Sets whether the compiler should preserve all bindings, even when those
  ## bindings are not used.

proc setAutoMapLocations*(options: ShadercCompileOptionsT; autoMap: bool) {.
    importc: "shaderc_compile_options_set_auto_map_locations".}
  ## Sets whether the compiler should automatically assign locations to
  ## uniform variables that don't have explicit locations in the shader source.

proc setHlslRegisterSetAndBindingForStage*(
    options: ShadercCompileOptionsT; shaderKind: ShadercShaderKind;
    reg: cstring; `set`: cstring; binding: cstring) {.
    importc: "shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage".}
  ## Sets a descriptor set and binding for an HLSL register in the given stage.
  ## This method keeps a copy of the string data.

proc setHlslRegisterSetAndBinding*(options: ShadercCompileOptionsT; reg: cstring;
    `set`: cstring; binding: cstring) {.
    importc: "shaderc_compile_options_set_hlsl_register_set_and_binding".}
  ## Like shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage,
  ## but affects all shader stages.

proc setHlslFunctionality1*( options: ShadercCompileOptionsT; enable: bool) {.
    importc: "shaderc_compile_options_set_hlsl_functionality1".}
  ## Sets whether the compiler should enable extension
  ## SPV_GOOGLE_hlsl_functionality1.

proc setHlsl16bitTypes*(options: ShadercCompileOptionsT; enable: bool) {.
    importc: "shaderc_compile_options_set_hlsl_16bit_types".}
  ## Sets whether 16-bit types are supported in HLSL or not.

proc setVulkanRulesRelaxed*(options: ShadercCompileOptionsT; enable: bool) {.
    importc: "shaderc_compile_options_set_vulkan_rules_relaxed".}
  ## Enables or disables relaxed Vulkan rules.
  ##
  ## This allows most OpenGL shaders to compile under Vulkan semantics.

proc setInvertY*(options: ShadercCompileOptionsT; enable: bool) {.
    importc: "shaderc_compile_options_set_invert_y".}
  ## Sets whether the compiler should invert position.Y output in vertex shader.

proc setNanClamp*(options: ShadercCompileOptionsT; enable: bool) {.
    importc: "shaderc_compile_options_set_nan_clamp".}
  ## Sets whether the compiler generates code for max and min builtins which,
  ## if given a NaN operand, will return the other operand. Similarly, the clamp
  ## builtin will favour the non-NaN operands, as if clamp were implemented
  ## as a composition of max and min.

proc compileIntoSpv*(compiler: ShadercCompilerT; sourceText: cstring;
    sourceTextSize: csize_t; shaderKind: ShadercShaderKind;
    inputFileName: cstring; entryPointName: cstring;
    additionalOptions: ShadercCompileOptionsT): ShadercCompilationResultT {.
    importc: "shaderc_compile_into_spv".}
  ## Takes a GLSL source string and the associated shader kind, input file
  ## name, compiles it according to the given additional_options. If the shader
  ## kind is not set to a specified kind, but shaderc_glslc_infer_from_source,
  ## the compiler will try to deduce the shader kind from the source
  ## string and a failure in deducing will generate an error. Currently only
  ## #pragma annotation is supported. If the shader kind is set to one of the
  ## default shader kinds, the compiler will fall back to the default shader
  ## kind in case it failed to deduce the shader kind from source string.
  ## The input_file_name is a null-termintated string. It is used as a tag to
  ## identify the source string in cases like emitting error messages. It
  ## doesn't have to be a 'file name'.
  ## The source string will be compiled into SPIR-V binary and a
  ## shaderc_compilation_result will be returned to hold the results.
  ## The entry_point_name null-terminated string defines the name of the entry
  ## point to associate with this GLSL source. If the additional_options
  ## parameter is not null, then the compilation is modified by any options
  ## present.  May be safely called from multiple threads without explicit
  ## synchronization. If there was failure in allocating the compiler object,
  ## null will be returned.

proc compileIntoSpvAssembly*(compiler: ShadercCompilerT; sourceText: cstring;
    sourceTextSize: csize_t; shaderKind: ShadercShaderKind;
    inputFileName: cstring; entryPointName: cstring;
    additionalOptions: ShadercCompileOptionsT): ShadercCompilationResultT {.
    importc: "shaderc_compile_into_spv_assembly".}
  ## Like shaderc_compile_into_spv, but the result contains SPIR-V assembly text
  ## instead of a SPIR-V binary module.  The SPIR-V assembly syntax is as defined
  ## by the SPIRV-Tools open source project.

proc compileIntoPreprocessedText*(compiler: ShadercCompilerT;
    sourceText: cstring; sourceTextSize: csize_t; shaderKind: ShadercShaderKind;
    inputFileName: cstring; entryPointName: cstring;
    additionalOptions: ShadercCompileOptionsT): ShadercCompilationResultT {.
    importc: "shaderc_compile_into_preprocessed_text".}
  ## Like shaderc_compile_into_spv, but the result contains preprocessed source
  ## code instead of a SPIR-V binary module

proc assembleIntoSpv*(compiler: ShadercCompilerT; sourceAssembly: cstring;
    sourceAssemblySize: csize_t; additionalOptions: ShadercCompileOptionsT): ShadercCompilationResultT {.
    importc: "shaderc_assemble_into_spv".}
  ## Takes an assembly string of the format defined in the SPIRV-Tools project
  ## (https://github.com/KhronosGroup/SPIRV-Tools/blob/master/syntax.md),
  ## assembles it into SPIR-V binary and a shaderc_compilation_result will be
  ## returned to hold the results.
  ## The assembling will pick options suitable for assembling specified in the
  ## additional_options parameter.
  ## May be safely called from multiple threads without explicit synchronization.
  ## If there was failure in allocating the compiler object, null will be
  ## returned.

proc release*(result: ShadercCompilationResultT) {.
    importc: "shaderc_result_release".}
  ## The following functions, operating on shaderc_compilation_result_t objects,
  ## offer only the basic thread-safety guarantee.
  ## Releases the resources held by the result object. It is invalid to use the
  ## result object for any further operations.

proc getLength*(result: ShadercCompilationResultT): csize_t {.
    importc: "shaderc_result_get_length".}
  ## Returns the number of bytes of the compilation output data in a result
  ## object.

proc getNumWarnings*(result: ShadercCompilationResultT): csize_t {.
    importc: "shaderc_result_get_num_warnings".}
  ## Returns the number of warnings generated during the compilation.

proc getNumErrors*(result: ShadercCompilationResultT): csize_t {.
    importc: "shaderc_result_get_num_errors".}
  ## Returns the number of errors generated during the compilation.

proc getCompilationStatus*(a1: ShadercCompilationResultT): ShadercCompilationStatus {.
    importc: "shaderc_result_get_compilation_status".}
  ## Returns the compilation status, indicating whether the compilation succeeded,
  ## or failed due to some reasons, like invalid shader stage or compilation
  ## errors.

proc getBytes*(result: ShadercCompilationResultT): cstring {.
    importc: "shaderc_result_get_bytes".}
  ## Returns a pointer to the start of the compilation output data bytes, either
  ## SPIR-V binary or char string. When the source string is compiled into SPIR-V
  ## binary, this is guaranteed to be castable to a uint32_t*. If the result
  ## contains assembly text or preprocessed source text, the pointer will point to
  ## the resulting array of characters.

proc getErrorMessage*(result: ShadercCompilationResultT): cstring {.
    importc: "shaderc_result_get_error_message".}
  ## Returns a null-terminated string that contains any error messages generated
  ## during the compilation.

proc getSpvVersion*(version: ptr cuint; revision: ptr cuint) {.
    importc: "shaderc_get_spv_version".}
  ## Provides the version & revision of the SPIR-V which will be produced

proc parseVersionProfile*(str: cstring; version: ptr cint;
    profile: ptr ShadercProfile): bool {.importc: "shaderc_parse_version_profile".}
  ## Parses the version and profile from a given null-terminated string
  ## containing both version and profile, like: '450core'. Returns false if
  ## the string can not be parsed. Returns true when the parsing succeeds. The
  ## parsed version and profile are returned through arguments.

{.pop.}
