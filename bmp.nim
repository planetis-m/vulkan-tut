import flatty/binny, chroma

const
  bmpSignature = "BM"
  LCS_sRGB = 0x73524742

proc encodeDib*(width, height: int, data: openArray[ColorRGBA]): string {.raises: [].} =
  ## Encodes an image into a DIB.

  # BITMAPINFO containing BITMAPV5HEADER
  result.addUint32(124) # Size of this header
  result.addInt32(width.int32) # Signed integer
  result.addInt32(height.int32) # Signed integer
  result.addUint16(1) # Must be 1 (color planes)
  result.addUint16(32) # Bits per pixels, only support RGBA
  result.addUint32(3) # BI_BITFIELDS, no pixel array compression used
  result.addUint32(32) # Size of the raw bitmap data (including padding)
  result.addUint32(2835) # Print resolution of the image
  result.addUint32(2835) # Print resolution of the image
  result.addUint32(0) # Number of colors in the palette
  result.addUint32(0) # 0 means all colors are important
  result.addUint32(uint32(0x000000FF)) # Red channel
  result.addUint32(uint32(0x0000FF00)) # Green channel
  result.addUint32(uint32(0x00FF0000)) # Blue channel
  result.addUint32(uint32(0xFF000000)) # Alpha channel
  result.addUint32(LCS_sRGB) # Color space
  result.setLen(result.len + 64) # Unused
  result.addUint32(0) # BITMAPINFO bmiColors 0
  result.addUint32(0) # BITMAPINFO bmiColors 1
  result.addUint32(0) # BITMAPINFO bmiColors 2

  for y in 0 ..< height:
    for x in 0 ..< width:
      let rgba = data[(height - y - 1)*width + x]
      result.addUint32(cast[uint32](rgba))

proc encodeBmp*(width, height: int, data: openArray[ColorRGBA]): string {.raises: [].} =
  ## Encodes an image into the BMP file format.

  # BMP Header
  result.add(bmpSignature) # The header field used to identify the BMP
  result.addUint32(0) # The size of the BMP file in bytes
  result.addUint16(0) # Reserved
  result.addUint16(0) # Reserved
  result.addUint32(14 + 12 + 124) # The offset to the pixel array

  # DIB
  result.add(encodeDib(width, height, data))

  result.writeUint32(2, result.len.uint32)
