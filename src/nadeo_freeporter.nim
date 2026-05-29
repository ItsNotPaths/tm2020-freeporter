## nadeo-freeporter — a native Linux replacement for NadeoImporter.exe (and the
## .NET tooling Blendermania shells out to). Command-line only: it takes a
## Blender-exported mesh (the tail end of the FM4 -> Blender -> TM2020 pipeline)
## and writes Trackmania 2020 `.Item.Gbx` / `.Mesh.Gbx` without Wine.
##
## CLI shape mirrors the tool it replaces so existing callers map cleanly:
##   nadeo-freeporter mesh <path.fbx>
##   nadeo-freeporter item <path.fbx>
##
## The importer pipeline (FBX/OBJ parse -> material match -> CPlugCrystal /
## CPlugSolid2Model -> CGameItemModel) lands in sibling modules as it comes
## online. This file is just the entry point / arg dispatch.

import std/[os, strutils]
import ufbx
import gbx

const usageText = """
nadeo-freeporter — Linux mesh -> TM2020 .Item.Gbx importer

usage:
  nadeo-freeporter mesh <path>     build a .Mesh.Gbx from a mesh file
  nadeo-freeporter item <path>     build a .Item.Gbx from a mesh file
  nadeo-freeporter gbx <path>      debug: parse a .Gbx and dump header + body
  nadeo-freeporter --help          show this help

(scaffold: argument dispatch only; import pipeline not yet wired)
"""

type Mode = enum mMesh, mItem, mGbx

proc hexDump(b: seq[byte], n: int): string =
  ## First `n` bytes as hex, space-separated, for a quick eyeball.
  let m = min(n, b.len)
  result = ""
  for i in 0 ..< m:
    if i > 0: result.add ' '
    result.add toHex(b[i])

proc runGbx(path: string): int =
  let (info, body) = loadGbx(path)
  echo "GBX: ", path
  echo "  version:        ", info.version
  echo "  format:         ", info.format
  echo "  refTable compr: ", info.refTableCompression
  echo "  body compr:     ", info.bodyCompression
  echo "  class id:       0x", toHex(info.classId)
  echo "  user data len:  ", info.userDataLen
  echo "  num nodes:      ", info.numNodes
  echo "  external nodes: ", info.numExternalNodes
  echo "  body (raw):     ", info.compressedBodySize, " -> ",
    info.uncompressedBodySize, " bytes"
  echo "  body[0..31]:    ", hexDump(body, 32)
  return 0

proc run(mode: Mode, path: string): int =
  if not fileExists(path):
    stderr.writeLine "error: file not found: " & path
    return 1

  if mode == mGbx:
    return runGbx(path)

  if mode == mMesh:
    # Front-end smoke test: parse the FBX via ufbx and dump the extracted
    # geometry. (The .Mesh.Gbx / .Shape.Gbx writers are not wired yet.)
    let (ok, err, m) = loadFbx(path)
    if not ok:
      stderr.writeLine "error: failed to read FBX '" & path & "': " & err
      return 1

    let nPos = m.positions.len div 3
    let nCorners = m.cornerPos.len
    echo "FBX: ", path
    echo "  positions: ", nPos
    echo "  corners:   ", nCorners
    echo "  faces:     ", m.faces.len
    echo "  materials: ", m.materials.len
    for i, name in m.materials:
      echo "    [", i, "] ", name

    # Bounding box, as a cheap sanity check that positions are sane.
    if nPos > 0:
      var lo = [m.positions[0], m.positions[1], m.positions[2]]
      var hi = lo
      for v in 0 ..< nPos:
        for a in 0 .. 2:
          let c = m.positions[v * 3 + a]
          if c < lo[a]: lo[a] = c
          if c > hi[a]: hi[a] = c
      echo "  bbox min:  ", lo[0], " ", lo[1], " ", lo[2]
      echo "  bbox max:  ", hi[0], " ", hi[1], " ", hi[2]

    stderr.writeLine "nadeo-freeporter: .Mesh.Gbx writer not implemented yet."
    return 2

  stderr.writeLine "nadeo-freeporter: Item import of '" & path &
    "' is not implemented yet."
  return 2

proc main(): int =
  let args = commandLineParams()
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    stdout.write usageText
    return (if args.len == 0: 1 else: 0)

  case args[0].toLowerAscii
  of "mesh", "item", "gbx":
    if args.len < 2:
      stderr.writeLine "error: '" & args[0] & "' needs a <path>"
      return 1
    let mode = case args[0].toLowerAscii
               of "mesh": mMesh
               of "item": mItem
               else: mGbx
    return run(mode, args[1])
  else:
    stderr.writeLine "error: unknown command '" & args[0] & "'\n"
    stdout.write usageText
    return 1

when isMainModule:
  quit main()
