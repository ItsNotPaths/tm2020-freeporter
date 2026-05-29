## Decompress two NadeoImporter runs of the same fixture and diff their bodies,
## reporting every differing byte range with hex context — to tell apart benign
## non-determinism (the fileWriteTime i64 in the body) from real non-determinism
## (lightmap atlas packing). Pairs with tests/gen/determinism_check.sh.
## Run: nim c -r tests/mesh_diff.nim [stem]   (default 03_unit_cube)

import std/[os, strutils]
import "../src/gbx"

proc hexRange(b: seq[byte], lo, hi: int): string =
  result = ""
  for k in lo ..< min(hi, b.len): result.add toHex(b[k]) & " "

let stem = if paramCount() >= 1: paramStr(1) else: "03_unit_cube"
let dir = "/tmp/nfp_determinism"
let pa = dir & "/" & stem & ".runA.Mesh.gbx"
let pb = dir & "/" & stem & ".runB.Mesh.gbx"
if not fileExists(pa) or not fileExists(pb):
  echo "missing run captures in ", dir, " — run determinism_check.sh first."; quit 0

let (ia, a) = loadGbx(pa)
let (ib, b) = loadGbx(pb)
echo "runA body = ", a.len, "B   runB body = ", b.len, "B"
echo "compressed: ", ia.compressedBodySize, " vs ", ib.compressedBodySize

if a.len != b.len:
  echo "BODY LENGTHS DIFFER — structural non-determinism."
  quit 0

# Collect contiguous differing ranges.
var ranges: seq[(int,int)] = @[]
var i = 0
while i < a.len:
  if a[i] != b[i]:
    let start = i
    while i < a.len and a[i] != b[i]: inc i
    ranges.add (start, i)
  else:
    inc i

if ranges.len == 0:
  echo "DECOMPRESSED BODIES IDENTICAL — fully deterministic (raw diff was just LZO)."
  quit 0

echo "DECOMPRESSED BODIES DIFFER in ", ranges.len, " range(s):"
for (lo, hi) in ranges:
  echo "  @", lo, " .. ", hi, " (", hi-lo, " B)"
  echo "    A: ", hexRange(a, lo, hi)
  echo "    B: ", hexRange(b, lo, hi)
echo "Total differing bytes: ", block:
  var n = 0
  for (lo,hi) in ranges: n += hi-lo
  n
