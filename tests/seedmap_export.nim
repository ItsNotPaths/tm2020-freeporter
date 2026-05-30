## Export a ladder of seed-map variants for in-game removal testing.
##
## Writes, to the target dir (arg 1, else the hardcoded Trackmania Maps path):
##   fp00_faithful.Map.Gbx        — full seed, no drops (must load; sanity)
##   fp01..fpNN_drop_<chunk>      — cumulative removal, BACK-TO-FRONT (last body
##                                  chunk first). Back-to-front is the safe order:
##                                  GBX lookback-string back-refs point backwards,
##                                  so removing a later chunk can't desync an
##                                  earlier one's Ids. Load them in order; the first
##                                  that fails names the chunk that step removed.
## Each file gets a unique MapUid + MapName so TM doesn't dedupe them and they're
## distinguishable in the browser. A _KEY.txt manifest lists what each file dropped.
##
## Run: nim c -r tests/seedmap_export.nim [outDir]

import std/[os, strutils, algorithm]
import "../src/gbx"
import "../src/seedmap"

const defaultDir = "/run/media/paths/SSS-Games/SteamLibrary/steamapps/compatdata/2225070/pfx/drive_c/users/steamuser/Documents/Trackmania/Maps/My Maps/freeporter-tests"
const baseUid = "BA8xleqTz5SzrCSk7ghTMuqKrhc"
const b64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

proc uidFor(k: int): string =
  ## Unique UID: base with its last two chars replaced by a base64 encoding of k.
  result = baseUid[0 ..< baseUid.len - 2] & b64[(k div 62) mod 62] & b64[k mod 62]

proc sanitize(s: string): string =
  result = ""
  for c in s:
    result.add (if c in {'a'..'z','A'..'Z','0'..'9'}: c else: '_')

proc main() =
  let outDir = if paramCount() >= 1: paramStr(1) else: defaultDir
  createDir(outDir)
  let (_, body) = loadSeed()

  # Skippable chunks, back-to-front (descending body offset).
  var skip: seq[Segment] = @[]
  for s in segments(body):
    if s.skippable: skip.add s
  skip.sort(proc(a, b: Segment): int = cmp(b.lo, a.lo))

  var key = "# freeporter seed-map removal ladder (cumulative, back-to-front)\n"
  key.add "# load in order; first one that fails => that step's chunk is required\n\n"

  # Baseline.
  block:
    let nm = "fp00_faithful.Map.Gbx"
    saveSeedMapGbxNamed(outDir / nm, @[], uidFor(0), "fp00 faithful")
    let sz = getFileSize(outDir / nm)
    key.add nm & "  | no drops | " & $sz & " B\n"
    echo "fp00 faithful  ", sz, " B"

  # Cumulative ladder.
  var drop: seq[uint32] = @[]
  for k, s in skip:
    drop.add s.chunkId
    let idx = align($(k + 1), 2, '0')
    let nm = "fp" & idx & "_drop_0x" & toHex(s.chunkId) & "_" & sanitize(s.label) & ".Map.Gbx"
    let mapName = "fp" & idx & " -" & s.label
    saveSeedMapGbxNamed(outDir / nm, drop, uidFor(k + 1), mapName)
    let sz = getFileSize(outDir / nm)
    key.add nm & "  | drop 0x" & toHex(s.chunkId) & " " & s.label &
            " (" & $(s.hi - s.lo) & " B raw) | cumulative " & $drop.len &
            " chunks | " & $sz & " B\n"
    echo "fp", idx, " -0x", toHex(s.chunkId), " ", alignLeft(s.label, 28), " ", sz, " B"

  writeFile(outDir / "_KEY.txt", key)
  echo "\nwrote ", skip.len + 1, " maps + _KEY.txt to:\n  ", outDir

main()
