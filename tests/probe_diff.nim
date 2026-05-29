## Differential probe — raw bytes + full-precision floats, one value per file.
import std/strutils
import "../src/gbx"

proc f32(s: seq[byte], off: int): float32 =
  let u = uint32(s[off]) or (uint32(s[off+1]) shl 8) or
          (uint32(s[off+2]) shl 16) or (uint32(s[off+3]) shl 24)
  cast[float32](u)

let (_, a) = loadGbx("tests/gen/golden/01_triangle.Shape.gbx")
let (_, b) = loadGbx("tests/gen/golden/04_triangle_shifted.Shape.gbx")

# Raw 8 bytes around the diff (32..39) for both, as hex.
proc hexRange(s: seq[byte], lo, hi: int): string =
  result = ""
  for i in lo ..< hi: result.add toHex(s[i]) & " "
writeFile("/tmp/q_a_hex.txt", hexRange(a, 32, 40) & "\n")
writeFile("/tmp/q_b_hex.txt", hexRange(b, 32, 40) & "\n")

# Full-precision float at 36 for both.
writeFile("/tmp/q_a36.txt", $f32(a, 36) & "\n")
writeFile("/tmp/q_b36.txt", $f32(b, 36) & "\n")

# All float32 values at every 4-aligned offset 0..63, body a, to see structure.
var s = ""
var off = 0
while off + 4 <= a.len and off < 96:
  s.add $off & ": " & $f32(a, off) & "\n"
  off += 4
writeFile("/tmp/q_a_floats.txt", s)
