import std/dynlib, vulkan, renderdoc_app

when defined(android):
  const rDocDLL = "libVkLayer_GLES_RenderDoc.so"
when defined(linux):
  const rDocDLL = "librenderdoc.so"
elif defined(windows):
  const rDocDLL = "renderdoc.dll"
elif defined(macosx):
  const rDocDLL = "librenderdoc.dylib"
else:
  {.error: "RenderDoc integration not implemented on this platform".}

var
  initialized = false
  rDocAPI: ptr RENDERDOC_API_1_6_0 = nil
  rDocGetAPI: pRENDERDOC_GetAPI

proc getRdocAPI(): ptr RENDERDOC_API_1_6_0 =
  if initialized:
    return rDocAPI
  initialized = true
  let rDocHandleDLL = loadLib(rDocDLL)
  if isNil(rDocHandleDLL):
    raise newException(LibraryError, "Failed to load " & rDocDLL)
  rDocGetAPI = cast[pRENDERDOC_GetAPI](checkedSymAddr(rDocHandleDLL, "RENDERDOC_GetAPI"))
  if rDocGetAPI.isNil:
    raise newException(LibraryError, "Failed to find RENDERDOC_GetAPI")
  let ret = rDocGetAPI(eRENDERDOC_API_Version_1_6_0, cast[ptr pointer](addr rDocAPI))
  if ret != 1:
    rDocAPI = nil
    raise newException(LibraryError, "RenderDoc initialization failed")
  result = rDocAPI

proc startFrameCapture*(instance: VkInstance) =
  let rDocAPI = getRdocApi()
  if not rDocAPI.isNil:
    let device = RENDERDOC_DEVICEPOINTER_FROM_VKINSTANCE(instance)
    rDocAPI.StartFrameCapture(device, nil)

proc endFrameCapture*(instance: VkInstance) =
  let rDocAPI = getRdocApi()
  if not rDocAPI.isNil:
    let device = RENDERDOC_DEVICEPOINTER_FROM_VKINSTANCE(instance)
    discard rDocAPI.EndFrameCapture(device, nil)
