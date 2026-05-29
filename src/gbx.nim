## Low-level GBX reader — hand-written, transcribed from gbx-net's serializer
## (vendor/gbx-net/Src/GBX.NET/Serialization). Scope for now: parse the header,
## skip user data, read the (usually empty) reference table, and decompress the
## LZO body. This is the M2 foundation: prove the framing + LZO path against the
## goldens before parsing body chunks or writing anything.
##
## Deliberately simple per the project rule: a cursor over a seq[byte] with
## explicit little-endian reads. No generics, no chunk codegen.

import std/[streams, strutils]
import lzo

type
  GbxCompression* = enum
    gcUnspecified, gcCompressed, gcUncompressed

  GbxInfo* = object
    ## Everything we pull off the header + framing.
    version*: uint16
    format*: char            # 'B' binary, 'T' text
    refTableCompression*: GbxCompression
    bodyCompression*: GbxCompression
    unknownByte*: char
    classId*: uint32
    userDataLen*: int
    numNodes*: int
    numExternalNodes*: int
    uncompressedBodySize*: int
    compressedBodySize*: int

  GbxReader* = object
    ## Cursor over an in-memory buffer.
    data: seq[byte]
    pos: int
    # Lookback-string ("Id") state, per gbx-net's GbxReader.
    idVersion: int           # -1 until first Id read
    idDict: seq[string]      # stored strings, 1-based via the index math

proc initGbxReader*(data: seq[byte]): GbxReader =
  GbxReader(data: data, pos: 0, idVersion: -1, idDict: @[])

proc remaining*(r: GbxReader): int = r.data.len - r.pos
proc pos*(r: GbxReader): int = r.pos

proc need(r: GbxReader, n: int) =
  if r.pos + n > r.data.len:
    raise newException(IOError, "GBX read past end (need " & $n &
      " at " & $r.pos & "/" & $r.data.len & ")")

proc readU8*(r: var GbxReader): uint8 =
  r.need(1)
  result = r.data[r.pos]
  inc r.pos

proc readU16*(r: var GbxReader): uint16 =
  r.need(2)
  result = uint16(r.data[r.pos]) or (uint16(r.data[r.pos + 1]) shl 8)
  r.pos += 2

proc readU32*(r: var GbxReader): uint32 =
  r.need(4)
  result = uint32(r.data[r.pos]) or
           (uint32(r.data[r.pos + 1]) shl 8) or
           (uint32(r.data[r.pos + 2]) shl 16) or
           (uint32(r.data[r.pos + 3]) shl 24)
  r.pos += 4

proc readI32*(r: var GbxReader): int32 = cast[int32](r.readU32())

proc readBytes*(r: var GbxReader, n: int): seq[byte] =
  r.need(n)
  result = r.data[r.pos ..< r.pos + n]
  r.pos += n

proc skip*(r: var GbxReader, n: int) =
  r.need(n)
  r.pos += n

proc readString*(r: var GbxReader): string =
  ## Length-prefixed (int32) UTF-8 string.
  let n = int(r.readI32())
  if n < 0:
    raise newException(IOError, "negative string length " & $n)
  let b = r.readBytes(n)
  result = newString(n)
  for i in 0 ..< n: result[i] = char(b[i])

proc readId*(r: var GbxReader): string =
  ## Lookback string. First call reads the id version (must be >= 3); then each
  ## id is a u32: 0 = empty, bit30 set = new string follows, bit31 set =
  ## back-reference into the table. (gbx-net GbxReader.ReadIdIndex/ReadIdAsString.)
  if r.idVersion < 0:
    r.idVersion = int(r.readI32())
    if r.idVersion < 3:
      raise newException(IOError, "unsupported Id version " & $r.idVersion)
  let index = r.readU32()
  if index == 0:
    return ""
  if (index and 0x40000000'u32) != 0:
    let s = r.readString()
    r.idDict.add s
    return s
  if (index and 0xC0000000'u32) != 0:
    let refIndex = int(index and 0x3FFFFFFF'u32)
    # Stored strings are 1-based in gbx-net's dict math.
    if refIndex >= 1 and refIndex <= r.idDict.len:
      return r.idDict[refIndex - 1]
    return ""
  raise newException(IOError, "unsupported Id index 0x" & toHex(index))

proc toCompression(b: uint8): GbxCompression =
  case char(b)
  of 'C': gcCompressed
  of 'U': gcUncompressed
  else: gcUnspecified

proc parseHeader*(r: var GbxReader): GbxInfo =
  ## Header + framing up to (not including) the body bytes. Leaves the cursor at
  ## the first body byte. Per gbx-net GbxHeaderReader.Parse.
  let magic = r.readBytes(3)
  if magic != @[byte('G'), byte('B'), byte('X')]:
    raise newException(IOError, "not a GBX file (bad magic)")

  result.version = r.readU16()
  result.format = char(r.readU8())
  result.refTableCompression = toCompression(r.readU8())
  result.bodyCompression = toCompression(r.readU8())
  result.unknownByte = (if result.version >= 4: char(r.readU8()) else: 'R')

  result.classId = r.readU32()

  # User data (version >= 6): an int32 length, then that many bytes we skip for
  # now (header chunks aren't needed to reach the body).
  if result.version >= 6:
    result.userDataLen = int(r.readI32())
    if result.userDataLen > 0:
      r.skip(result.userDataLen)

  result.numNodes = int(r.readI32())

  # Reference table: int32 count; 0 means no external refs and the body follows.
  result.numExternalNodes = int(r.readI32())
  if result.numExternalNodes != 0:
    raise newException(IOError, "external reference tables not yet supported (" &
      $result.numExternalNodes & " nodes)")

proc readBody*(r: var GbxReader, info: var GbxInfo): seq[byte] =
  ## Read and (if needed) decompress the body. Returns the uncompressed bytes.
  case info.bodyCompression
  of gcCompressed:
    info.uncompressedBodySize = int(r.readU32())
    info.compressedBodySize = int(r.readU32())
    let comp = r.readBytes(info.compressedBodySize)
    result = lzoDecompress(comp, info.uncompressedBodySize)
  of gcUncompressed:
    result = r.readBytes(r.remaining)
    info.uncompressedBodySize = result.len
    info.compressedBodySize = result.len
  else:
    raise newException(IOError, "unknown body compression")

proc loadGbx*(path: string): tuple[info: GbxInfo, body: seq[byte]] =
  ## Read a .Gbx from disk: parse header, decompress body. Returns both.
  let s = newFileStream(path, fmRead)
  if s == nil:
    raise newException(IOError, "cannot open " & path)
  defer: s.close()
  let raw = cast[seq[byte]](s.readAll())
  var r = initGbxReader(raw)
  var info = r.parseHeader()
  let body = r.readBody(info)
  result = (info, body)
