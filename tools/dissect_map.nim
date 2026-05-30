## Throwaway: dump skippable-chunk map of a real .Map.Gbx and inspect the
## 0x040 (anchored objects) + 0x054 (embedded zip) regions to learn TM2020's
## actual chunk versions. Reuses the project's gbx + seedmap modules.
import std/[strformat, strutils, os]
import "../src/gbx"
import "../src/seedmap"

proc u32(b: seq[byte], i: int): uint32 =
  uint32(b[i]) or (uint32(b[i+1]) shl 8) or
    (uint32(b[i+2]) shl 16) or (uint32(b[i+3]) shl 24)

proc hexdump(b: seq[byte], lo, n: int): string =
  var parts: seq[string]
  for k in lo ..< min(lo + n, b.len):
    parts.add toHex(b[k].int, 2)
  parts.join(" ")

let path = paramStr(1)
let (info, body) = loadGbx(path)
echo &"body: {body.len} bytes decompressed"
echo "--- skippable chunks (id  offset  size  label) ---"
for s in segments(body):
  if s.skippable:
    echo &"  0x{toHex(s.chunkId)}  off={s.lo:>8}  size={s.hi - s.lo - 12:>8}  {s.label}"

for s in segments(body):
  if s.chunkId == 0x03043040'u32 or s.chunkId == 0x03043054'u32:
    let lo = s.lo
    echo &"\n=== chunk 0x{toHex(s.chunkId)} @ {lo} ==="
    echo &"  raw[0..47]: {hexdump(body, lo, 48)}"
    echo &"  chunkId    = 0x{toHex(u32(body, lo))}"
    echo &"  SKIP mark  = 0x{toHex(u32(body, lo+4))}"
    echo &"  dataSize   = {u32(body, lo+8)}"
    echo &"  Version    = {u32(body, lo+12)}        (chunk version)"
    echo &"  enc lead0  = {u32(body, lo+16)}        (WriteEncapsulated leading 0)"
    echo &"  enc length = {u32(body, lo+20)}"
    if s.chunkId == 0x03043040'u32:
      echo &"  DeprecVer  = {u32(body, lo+24)}        (expect 10)"
      echo &"  obj count  = {u32(body, lo+28)}"
      echo &"  first obj classId = 0x{toHex(u32(body, lo+32))}  (expect 03101000)"
    else:
      let identCount = u32(body, lo+24)
      echo &"  ident count= {identCount}"
      # after the ident array comes EmbeddedZipData: u32 len + bytes. With 0 idents
      # the zip-len u32 is at lo+28; dump its value + first zip bytes (PK header).
      if identCount == 0:
        let zipLen = u32(body, lo+28)
        echo &"  zip data len= {zipLen}"
        echo &"  zip[0..15]  = {hexdump(body, lo+32, 16)}   (50 4B = 'PK' zip)"
    if s.chunkId == 0x03043040'u32 and u32(body, lo+28) > 0'u32:
      # Walk the tail: at v7 the writer emits, after the 242 inline objects,
      # 5 arrays then snappedOnIndices. With no snapping all are count-0 except
      # snappedOnIndices = [count=242, then 242 x int(-1)]. Verify from the end.
      let chunkEnd = s.hi              # lo+12+dataSize
      var ffRun = 0
      var k = chunkEnd - 1
      while k >= 0 and body[k] == 0xFF: dec k; inc ffRun
      echo &"  trailing 0xFF bytes = {ffRun}  (expect 242*4 = 968 if all snap=-1)"
      let tailStart = chunkEnd - ffRun - 24
      echo &"  tail[{tailStart}..end]: {hexdump(body, tailStart, min(40, chunkEnd - tailStart))}"
      # Decode anchored object #0 (chunk 0x03101002 v7). Fresh reader at the ident
      # (lo+44): +24 DeprecVer, +28 count, +32 classId, +36 chunkId, +40 objVer, +44 ident.
      echo "  --- anchored object #0 (v7) ---"
      var r = initGbxReader(body[lo+44 ..< chunkEnd])
      let id = r.readId()
      let coll = r.readId()
      let author = r.readId()
      echo &"    ident.Id     = \"{id}\""
      echo &"    ident.Coll   = \"{coll}\"  (26 = Stadium2020)"
      echo &"    ident.Author = \"{author}\""
      let ypr = [r.readF32(), r.readF32(), r.readF32()]
      echo &"    YawPitchRoll = {ypr}"
      echo &"    BlockUnitCoord = [{r.readU8()}, {r.readU8()}, {r.readU8()}]"
      let anchor = r.readId()
      echo &"    AnchorTreeId = \"{anchor}\""
      let pos = [r.readF32(), r.readF32(), r.readF32()]
      echo &"    AbsolutePos  = {pos}"
      let waypoint = r.readI32()
      echo &"    Waypoint ref = {waypoint}  (-1 = null)"
      let flags = r.readU16()
      echo &"    Flags        = 0x{toHex(flags.int, 4)}  (PackDesc present iff bit2 set)"
      let pivot = [r.readF32(), r.readF32(), r.readF32()]
      echo &"    Pivot        = {pivot}"
      echo &"    Scale        = {r.readF32()}"
      # What separates inline objects? bytes right after object #0.
      let after = lo + 44 + r.pos()
      echo &"    bytes after obj#0 @rel {r.pos()}: {hexdump(body, after, 16)}"
