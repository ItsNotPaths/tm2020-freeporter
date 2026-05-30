## Seed-map round-trip gate (docs/map-gbx-builder.md §7.1).
##
## Proves the header/LZO/framing systems are correct: the map emitted by
## `seedmap` must, on the DECOMPRESSED body, be byte-identical to the seed
## resources/seed-void.Map.Gbx. The compressed file differs (we use LZO1X-1,
## Nadeo uses LZO1X-999) — fidelity is on the decompressed content, same as items.
##
## Run: nim c -r tests/seedmap_roundtrip.nim

import std/[os, strutils]
import "../src/gbx"
import "../src/seedmap"

const seedPath = "resources/seed-void.Map.Gbx"

proc main() =
  doAssert fileExists(seedPath), "missing " & seedPath
  let (seedInfo, seedBody) = loadSeed()

  # 1. With an explicit empty drop, the rebuilt body equals the seed body exactly.
  let body = buildSeedMapBody(@[])
  doAssert body.len == seedBody.len,
    "body length " & $body.len & " != seed " & $seedBody.len
  var firstDiff = -1
  for i in 0 ..< body.len:
    if body[i] != seedBody[i]: firstDiff = i; break
  doAssert firstDiff == -1, "body diverges at offset " & $firstDiff
  echo "[ok] rebuilt body byte-identical to seed (", body.len, " bytes)"

  # 2. Emit to disk (explicit empty drop), reload, re-check body + header fields.
  let outPath = getTempDir() / "seedmap_roundtrip.Map.Gbx"
  saveSeedMapGbx(outPath, @[])
  let (outInfo, outBody) = loadGbx(outPath)
  doAssert outBody == seedBody, "reloaded body != seed body"
  doAssert outInfo.classId == seedInfo.classId, "classId mismatch"
  doAssert outInfo.version == seedInfo.version, "version mismatch"
  doAssert outInfo.numNodes == seedInfo.numNodes, "numNodes mismatch"
  doAssert outInfo.userData == seedInfo.userData, "userData mismatch"
  removeFile(outPath)
  echo "[ok] emitted file reloads; body + header (class 0x", toHex(outInfo.classId),
       " v", outInfo.version, " nodes ", outInfo.numNodes, ") match seed"

  # 3. The DEFAULT (stripped) seed still parses and keeps the GrassRemover embed.
  let strippedPath = getTempDir() / "seedmap_stripped.Map.Gbx"
  saveSeedMapGbx(strippedPath)                 # default drop set
  let (sInfo, sBody) = loadGbx(strippedPath)
  doAssert sInfo.classId == seedInfo.classId and sInfo.numNodes == seedInfo.numNodes
  # GrassRemover must survive: its block ref (block data) and embedded def (0x054).
  proc has(b: seq[byte], pat: string): bool =
    for i in 0 .. b.len - pat.len:
      var ok = true
      for k in 0 ..< pat.len:
        if char(b[i+k]) != pat[k]: ok = false; break
      if ok: return true
    false
  doAssert sBody.has("GrassRemover.Block.Gbx"), "stripped seed lost GrassRemover!"
  removeFile(strippedPath)
  echo "[ok] default-stripped seed parses (", sBody.len, "B body) and keeps GrassRemover"

  echo "PASS"

main()
