## Extract the constant byte payloads needed to build .Item.Gbx verbatim:
## the header userData (decoded chunk table + per-chunk bytes) and the skippable
## chunk payloads (placement params, trailing item chunks). Run on two fixtures
## with different names to see which bytes vary. Run: nim c -r tests/item_extract.nim
import std/[strutils]
import "../src/gbx"

proc hx(b: openArray[byte]): string =
  for x in b: result.add toHex(x) & " "

proc dumpHeader(stem: string) =
  let (info, _) = loadGbx("tests/gen/golden/" & stem & ".Item.gbx")
  echo "=== ", stem, " userData (", info.userData.len, "B) ==="
  var r = initGbxReader(info.userData)
  let n = r.readI32()
  var sizes: seq[int]
  var ids: seq[uint32]
  for c in 0 ..< n:
    ids.add r.readU32(); sizes.add int(r.readU32() and 0x7FFFFFFF'u32)
  let dataStart = r.pos
  var off = dataStart
  for c in 0 ..< n:
    echo "  chunk 0x", toHex(ids[c]), " (", sizes[c], "B): ",
         hx(info.userData[off ..< off+sizes[c]])
    off += sizes[c]

proc dumpSkippables(stem: string) =
  ## Find every skippable chunk (marker 0x534B4950) in the body and print payload.
  let (_, body) = loadGbx("tests/gen/golden/" & stem & ".Item.gbx")
  echo "=== ", stem, " skippable chunk payloads ==="
  var i = 0
  while i + 12 <= body.len:
    var r = initGbxReader(body); r.skip(i)
    let id = r.readU32()
    if i + 8 <= body.len:
      var r2 = initGbxReader(body); r2.skip(i+4)
      let marker = r2.readU32()
      if marker == 0x534B4950'u32 and (id and 0xFF000000'u32) != 0:
        var r3 = initGbxReader(body); r3.skip(i+8)
        let sz = int(r3.readI32())
        if i+12+sz <= body.len:
          echo "  @", i, " chunk 0x", toHex(id), " (", sz, "B): ",
               hx(body[i+12 ..< i+12+sz])
          i += 12 + sz; continue
    inc i

dumpHeader("01_triangle")
dumpHeader("13_two_materials")
dumpSkippables("01_triangle")
dumpSkippables("13_two_materials")
