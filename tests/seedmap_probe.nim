## Seed-map characterization probe (docs/map-gbx-builder.md milestone 1).
##
## Loads resources/seed-void.Map.Gbx and prints the body's segment tiling: every
## skippable CGameCtnChallenge chunk found (the droppable units) plus the opaque
## "structural" spans between them. This is both the characterization of the seed
## and a check that the marker-scan tiling reconstructs the body exactly.
##
## Characterization + a regression check that segments() tiles the body contiguously
## (the map former relies on that tiling to locate the 0x040 chunk it replaces).
##
## Run: nim c -r tests/seedmap_probe.nim

import std/[strutils]
import "../src/gbx"
import "../src/seedmap"

proc main() =
  let (info, body) = loadSeed()
  echo "=== seed: class 0x", toHex(info.classId), " v", info.version,
       " nodes ", info.numNodes, " userData ", info.userDataLen,
       "B body ", body.len, "B ==="
  let segs = segments(body)

  var structBytes = 0
  var skipBytes = 0
  var skipCount = 0
  var rebuilt = 0
  for s in segs:
    let n = s.hi - s.lo
    rebuilt += n
    if s.skippable:
      inc skipCount; skipBytes += n
      echo "@", align($s.lo, 8), "  ", align($n, 9), "B  skippable 0x",
           toHex(s.chunkId), "  ", s.label
    else:
      structBytes += n
      echo "@", align($s.lo, 8), "  ", align($n, 9), "B  structural"

  echo "---"
  echo "segments: ", segs.len, " (", skipCount, " skippable, ",
       segs.len - skipCount, " structural)"
  echo "skippable bytes:  ", skipBytes
  echo "structural bytes: ", structBytes
  echo "tiling total:     ", rebuilt, " / body ", body.len,
       (if rebuilt == body.len: "  [ok contiguous]" else: "  [!! MISMATCH]")
  doAssert rebuilt == body.len, "tiling does not cover the body contiguously"

main()
