## LZO1X (de)compression — thin Nim FFI over the C shim in lzo_bridge.c, which
## wraps the vendored minilzo. GBX bodies are LZO1X-compressed. As with the ufbx
## binding we bind only the shim's flat procs and compile minilzo straight into
## the binary (no shared library).

import std/os

const
  minilzoDir = currentSourcePath().parentDir().parentDir() / "vendor" / "minilzo"
  srcDir     = currentSourcePath().parentDir()

{.passC: "-I" & minilzoDir.}
{.passC: "-I" & srcDir.}
{.compile: minilzoDir / "minilzo.c".}
{.compile: srcDir / "lzo_bridge.c".}

proc fp_lzo_decompress(src: ptr byte, srcLen: csize_t,
                       dst: ptr byte, dstCap: csize_t,
                       outLen: ptr csize_t): cint
  {.importc, header: "lzo_bridge.h".}

proc fp_lzo_compress(src: ptr byte, srcLen: csize_t,
                     dst: ptr byte, outLen: ptr csize_t): cint
  {.importc, header: "lzo_bridge.h".}

proc fp_lzo_compress_bound(srcLen: csize_t): csize_t
  {.importc, header: "lzo_bridge.h".}

proc lzoDecompress*(src: openArray[byte], uncompressedSize: int): seq[byte] =
  ## Decompress `src` to exactly `uncompressedSize` bytes (the size the GBX body
  ## header records). Raises on any LZO error or size mismatch.
  result = newSeq[byte](uncompressedSize)
  if uncompressedSize == 0:
    return
  var produced: csize_t = 0
  let rc = fp_lzo_decompress(
    unsafeAddr src[0], csize_t(src.len),
    addr result[0], csize_t(uncompressedSize), addr produced)
  if rc != 0:
    raise newException(IOError, "LZO decompress failed (code " & $rc & ")")
  if int(produced) != uncompressedSize:
    raise newException(IOError, "LZO decompress size mismatch: got " &
      $int(produced) & ", expected " & $uncompressedSize)

proc lzoCompress*(src: openArray[byte]): seq[byte] =
  ## Compress `src` with LZO1X-1. Returns the compressed bytes.
  let bound = int(fp_lzo_compress_bound(csize_t(src.len)))
  var buf = newSeq[byte](bound)
  if src.len == 0:
    # minilzo still emits an end-of-stream marker for empty input; run it.
    var produced0: csize_t = 0
    let rc0 = fp_lzo_compress(nil, 0, addr buf[0], addr produced0)
    if rc0 != 0:
      raise newException(IOError, "LZO compress failed (code " & $rc0 & ")")
    buf.setLen(int(produced0))
    return buf
  var produced: csize_t = 0
  let rc = fp_lzo_compress(
    unsafeAddr src[0], csize_t(src.len), addr buf[0], addr produced)
  if rc != 0:
    raise newException(IOError, "LZO compress failed (code " & $rc & ")")
  buf.setLen(int(produced))
  result = buf
