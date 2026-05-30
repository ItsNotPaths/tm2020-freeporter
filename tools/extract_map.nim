## Throwaway: extract every anchored object from a real .Map.Gbx (chunk 0x040) into a
## freeporter/blendermania map config JSON, so we can re-emit the same placements via
## `nadeo-freeporter map` and A/B the result in-game against the original.
##
## usage: extract_map <source.Map.Gbx> <out-config.json> <target-output.Map.Gbx>
import std/[json, os, strutils]
import "../src/gbx"
import "../src/seedmap"

proc u32(b: seq[byte], i: int): uint32 =
  uint32(b[i]) or (uint32(b[i+1]) shl 8) or
    (uint32(b[i+2]) shl 16) or (uint32(b[i+3]) shl 24)

let src = paramStr(1)
let outCfg = paramStr(2)
let targetMap = paramStr(3)

let (_, body) = loadGbx(src)
var lo = -1
for s in segments(body):
  if s.chunkId == 0x03043040'u32: lo = s.lo
if lo < 0: quit("no 0x03043040 chunk in " & src, 1)

# One reader, started at DeprecVersion (lo+24), kept stateful so the Id lookback heap
# accumulates across objects exactly as the writer built it.
let chunkEnd = lo + 12 + int(u32(body, lo + 8))
var r = initGbxReader(body[lo + 24 ..< chunkEnd])
let deprec = r.readU32()
let count = r.readU32()
echo "DeprecVersion=", deprec, "  count=", count

var items = newJArray()
proc vec(x, y, z: float32): JsonNode =
  %*{"X": x, "Y": y, "Z": z}

for i in 0 ..< int(count):
  let cls = r.readU32()
  let chk = r.readU32()
  let ver = r.readU32()
  if cls != 0x03101000'u32 or chk != 0x03101002'u32:
    quit("object " & $i & ": unexpected class/chunk 0x" & toHex(cls) & "/0x" & toHex(chk), 1)
  let idPath = r.readId()
  discard r.readId()                      # collection (26)
  discard r.readId()                      # author
  let ry = r.readF32(); let rp = r.readF32(); let rr = r.readF32()  # YawPitchRoll
  discard r.readU8(); discard r.readU8(); discard r.readU8()        # BlockUnitCoord
  discard r.readId()                      # AnchorTreeId
  let px = r.readF32(); let py = r.readF32(); let pz = r.readF32()  # AbsolutePosition
  let waypoint = r.readI32()
  if waypoint != -1:
    quit("object " & $i & ": non-null waypoint not supported by this extractor", 1)
  let flags = r.readU16()
  let vx = r.readF32(); let vy = r.readF32(); let vz = r.readF32()  # Pivot (v5+)
  discard r.readF32()                      # Scale (v6+)
  if (flags and 4) != 0:
    quit("object " & $i & ": Flags&4 (PackDesc) not supported by this extractor", 1)
  let marker = r.readU32()
  if marker != 0xFACADE01'u32:
    quit("object " & $i & ": missing 0xFACADE01 node-end (got 0x" & toHex(marker) & ")", 1)
  if ver != 7: discard                     # template assumes v7; just note via the marker check
  items.add %*{
    "Name": idPath.replace("\\", "/"),
    "Path": "",
    "Position": vec(px, py, pz),
    "Rotation": vec(ry, rp, rr),
    "Pivot": vec(vx, vy, vz)
  }

let cfg = %*{
  "MapPath": targetMap,
  "Items": items,
  "Blocks": newJArray(),
  "ShouldOverwrite": true,
  "MapSuffix": "_modified",
  "CleanBlocks": true,
  "CleanItems": true,
  "Env": "Stadium2020"
}
writeFile(outCfg, pretty(cfg))
echo "wrote ", outCfg, "  (", items.len, " items -> ", targetMap, ")"
