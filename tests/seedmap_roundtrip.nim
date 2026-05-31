## Seed round-trip gate (docs/map-gbx-builder.md §7.1).
##
## Proves the header/LZO/framing systems are correct: re-emitting the baked seed via
## the shared GBX core (seedMapInfo + saveGbx) and reloading must be byte-identical on
## the DECOMPRESSED body (the file itself differs — we use LZO1X-1, Nadeo LZO1X-999).
## Also checks the shipped, freeporter-branded seed still carries the GrassRemover embed.
##
## Run: nim c -r tests/seedmap_roundtrip.nim

import std/[os, strutils]
import "../src/gbx"
import "../src/seedmap"

const seedPath = "resources/seed-void.Map.Gbx"

proc has(b: seq[byte], pat: string): bool =
  for i in 0 .. b.len - pat.len:
    var ok = true
    for k in 0 ..< pat.len:
      if char(b[i+k]) != pat[k]: ok = false; break
    if ok: return true
  false

proc main() =
  doAssert fileExists(seedPath), "missing " & seedPath
  let (seedInfo, seedBody) = loadSeed()

  # Re-emit the seed body via the shared GBX core, reload, compare body + header fields.
  let outPath = getTempDir() / "seedmap_roundtrip.Map.Gbx"
  saveGbx(outPath, seedMapInfo(), seedBody)
  let (outInfo, outBody) = loadGbx(outPath)
  doAssert outBody == seedBody, "reloaded body != seed body"
  doAssert outInfo.classId == seedInfo.classId, "classId mismatch"
  doAssert outInfo.version == seedInfo.version, "version mismatch"
  doAssert outInfo.numNodes == seedInfo.numNodes, "numNodes mismatch"
  doAssert outInfo.userData == seedInfo.userData, "userData mismatch"
  removeFile(outPath)
  echo "[ok] seed body round-trips byte-identical (", seedBody.len, "B); header class 0x",
       toHex(outInfo.classId), " v", outInfo.version, " nodes ", outInfo.numNodes

  # The shipped seed must still carry the GrassRemover (the no-grass void floor).
  doAssert seedBody.has("GrassRemover.Block.Gbx"), "seed lost GrassRemover!"
  echo "[ok] shipped seed keeps GrassRemover"

  echo "PASS"

main()
