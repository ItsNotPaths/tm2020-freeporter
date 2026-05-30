## One-off RE probe for G1 (lib-driven vertex format). Decompress the Mesh bodies
## of 01_triangle (PlatformTech, 2-layer) and 14_mat_grass (Grass, 1-layer) — same
## geometry, only the material/Link differs — and emit an annotated side-by-side
## hex dump + the contiguous differing ranges, so we can read off the 1-layer
## vertex format (decl list, stream flag, which UV set, vertex-data stride).
## Writes to /tmp/grass_diff.txt (stdout is unreliable on this volume).
## Run: nim c -r tests/grass_diff.nim

import std/[strutils]
import "../src/gbx"

const dir = "tests/gen/golden/"
let (_, a) = loadGbx(dir & "01_triangle.Mesh.gbx")   # 2-layer
let (_, b) = loadGbx(dir & "14_mat_grass.Mesh.gbx")  # 1-layer

var o = ""
o.add "01_triangle (PlatformTech, 2-layer) body = " & $a.len & " B\n"
o.add "14_mat_grass (Grass,       1-layer) body = " & $b.len & " B\n\n"

proc hexDump(b: seq[byte], title: string): string =
  result = "=== " & title & " (" & $b.len & " B) ===\n"
  var i = 0
  while i < b.len:
    var line = intToStr(i, 4) & ": "
    var asc = ""
    for k in i ..< min(i+16, b.len):
      line.add toHex(b[k]) & " "
      let c = char(b[k])
      asc.add (if c in {' '..'~'}: c else: '.')
    result.add line.alignLeft(54) & "|" & asc & "|\n"
    i += 16

o.add hexDump(a, "01_triangle 2-layer")
o.add "\n"
o.add hexDump(b, "14_mat_grass 1-layer")
o.add "\n=== contiguous differing ranges (aligned by offset) ===\n"
let n = min(a.len, b.len)
var i = 0
while i < n:
  if a[i] != b[i]:
    let s = i
    while i < n and a[i] != b[i]: inc i
    o.add "  [" & $s & ".." & $i & ") len " & $(i-s) & "\n"
    o.add "    A: "
    for k in s ..< i: o.add toHex(a[k]) & " "
    o.add "\n    B: "
    for k in s ..< i: o.add toHex(b[k]) & " "
    o.add "\n"
  else:
    inc i
if a.len != b.len:
  o.add "  (length differs by " & $(b.len - a.len) & " B; tail beyond " & $n & " not aligned)\n"

writeFile("/tmp/grass_diff.txt", o)
echo "wrote /tmp/grass_diff.txt  (A=", a.len, "B B=", b.len, "B)"
