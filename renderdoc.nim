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
  initialized* = false
  rdoc_api*: ptr RENDERDOC_API_1_6_0 = nil
  rdoc_getAPI: pRENDERDOC_GetAPI

proc getRdocApi*(): ptr RENDERDOC_API_1_6_0 =
  if initialized:
    return rdoc_api
  initialized = true
  let rDocHandleDLL = loadLib(rDocDLL)
  if isNil(rDocHandleDLL):
    raise newException(LibraryError, "Failed to load " & rDocDLL)
  rdoc_getAPI = cast[pRENDERDOC_GetAPI](checkedSymAddr(rDocHandleDLL, "RENDERDOC_GetAPI"))
  if rdoc_getAPI.isNil:
    raise newException(LibraryError, "Failed to find RENDERDOC_GetAPI")
  let ret = rdoc_getAPI(eRENDERDOC_API_Version_1_6_0, cast[ptr pointer](addr rdoc_api))
  if ret != 1:
    rdoc_api = nil
    raise newException(LibraryError, "RenderDoc initialization failed")
  result = rdoc_api

proc startRenderDocCapture*(instance: VkInstance) =
  let rdoc_api = getRdocApi()
  if rdoc_api.isNil:
    return
  let device = RENDERDOC_DEVICEPOINTER_FROM_VKINSTANCE(instance)
  rdoc_api.StartFrameCapture(device, nil)

proc endRenderDocCapture*(instance: VkInstance) =
  let rdoc_api = getRdocApi()
  if rdoc_api.isNil:
    return
  let device = RENDERDOC_DEVICEPOINTER_FROM_VKINSTANCE(instance)
  discard rdoc_api.EndFrameCapture(device, nil)
