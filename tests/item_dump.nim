## Quick raw dump of an .Item.Gbx: header userData hex (with header-chunk table
## decoded) + the full decompressed body hex. Orientation tool before the
## structured item_probe. Run: nim c -r tests/item_dump.nim [stem]
import std/[os, strutils]
import "../src/gbx"

proc hexdump(b: openArray[byte], base = 0) =
  var i = 0
  while i < b.len:
    var line = align($(base+i), 5) & "  "
    var asc = ""
    for k in 0 ..< 16:
      if i+k < b.len:
        line.add toHex(b[i+k]) & " "
        let c = char(b[i+k])
        asc.add (if c in {' '..'~'}: c else: '.')
      else: line.add "   "
    echo line, " ", asc
    i += 16

proc main() =
  let stem = if paramCount() >= 1: paramStr(1) else: "01_triangle"
  let path = "tests/gen/golden/" & stem & ".Item.gbx"
  let (info, body) = loadGbx(path)
  echo "=== ", path, " ==="
  echo "classId=0x", toHex(info.classId), " userDataLen=", info.userDataLen,
       " numNodes=", info.numNodes, " body=", body.len, "B"

  echo "\n--- header userData (", info.userData.len, "B) ---"
  # Header chunk table: i32 count, then count*(u32 id, u32 size&flags), then blobs.
  var r = initGbxReader(info.userData)
  let nChunks = r.readI32()
  echo "header chunks: ", nChunks
  var sizes: seq[int] = @[]
  for c in 0 ..< nChunks:
    let id = r.readU32()
    let sz = r.readU32()
    let heavy = (sz and 0x80000000'u32) != 0
    let realSz = int(sz and 0x7FFFFFFF'u32)
    sizes.add realSz
    echo "  chunk 0x", toHex(id), " size=", realSz, (if heavy: " (heavy)" else: "")
  echo "  [data starts @", r.pos, "]"
  hexdump(info.userData)

  echo "\n--- body (", body.len, "B) ---"
  hexdump(body)

main()
