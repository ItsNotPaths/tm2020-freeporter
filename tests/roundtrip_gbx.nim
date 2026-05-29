## Framing round-trip proof: for each golden, read header+framing+body, re-emit,
## and verify
##   (1) the pre-body bytes (header + framing) are BYTE-IDENTICAL to the golden,
##   (2) a full write->read cycle reproduces the decompressed body exactly.
## The compressed bytes themselves are NOT expected to match (we use LZO1X-1,
## Nadeo uses LZO1X-999) — correctness lives in the decompressed content.
import std/[streams, strutils, os]
import "../src/gbx"

proc readRaw(path: string): seq[byte] =
  let s = newFileStream(path, fmRead)
  doAssert s != nil, "cannot open " & path
  defer: s.close()
  cast[seq[byte]](s.readAll())

let goldens = [
  "tests/golden/CrownJewel_Tile.Shape.Gbx",
  "tests/golden/CrownJewel_Tile.Mesh.Gbx",
  "tests/golden/CrownJewel_Tile.Item.Gbx",
]

for path in goldens:
  let raw = readRaw(path)
  let (info, body) = loadGbx(path)
  let ours = writeGbx(info, body)

  # (1) pre-body region must be byte-identical.
  let goldHdr = raw[0 ..< info.bodyStart]
  let ourHdr = ours[0 ..< info.bodyStart]
  if goldHdr != ourHdr:
    echo "HEADER MISMATCH in ", path
    for i in 0 ..< min(goldHdr.len, ourHdr.len):
      if goldHdr[i] != ourHdr[i]:
        echo "  first diff at offset ", i, ": gold=", toHex(goldHdr[i]),
          " ours=", toHex(ourHdr[i])
        break
    quit(1)

  # (2) write -> read cycle must reproduce the decompressed body.
  var r = initGbxReader(ours)
  var info2 = r.parseHeader()
  let body2 = r.readBody(info2)
  if body2 != body:
    echo "BODY MISMATCH in ", path
    echo "  orig body len: ", body.len, "  round-trip body len: ", body2.len
    for i in 0 ..< min(body.len, body2.len):
      if body[i] != body2[i]:
        echo "  first diff at offset ", i, ": orig=", toHex(body[i]),
          " rt=", toHex(body2[i])
        break
    quit(1)
  doAssert info2.classId == info.classId
  doAssert info2.numNodes == info.numNodes
  doAssert info2.version == info.version

  echo path.splitPath.tail, ": header byte-identical (", info.bodyStart,
    " B), body round-trips (", body.len, " B; ours ",
    ours.len, " B vs golden ", raw.len, " B on disk)"

echo "gbx framing round-trip OK"
