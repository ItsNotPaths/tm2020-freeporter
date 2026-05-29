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

import std/[os, strutils, times]
import ufbx
import gbx
import shape
import mesh
import materials

const usageText = """
nadeo-freeporter — Linux mesh -> TM2020 .Item.Gbx importer

usage:
  nadeo-freeporter mesh <path>     build .Mesh.Gbx (+ .Shape.Gbx) from a mesh file
  nadeo-freeporter shape <path>    build only the .Shape.Gbx (collision) from a mesh
  nadeo-freeporter item <path>     build a .Item.Gbx from a mesh file
  nadeo-freeporter gbx <path>      debug: parse a .Gbx and dump header + body
  nadeo-freeporter --help          show this help

(shape & mesh: byte-exact vs NadeoImporter on the fixture ladder; item in progress)
"""

type Mode = enum mMesh, mItem, mGbx, mShape

proc unixTimeToWinTime(unixSecs: int64): int64 =
  ## Windows FILETIME: 100-nanosecond ticks since 1601-01-01 (Unix epoch is
  ## 11644473600 s later). Used for CPlugSolid2Model's embedded fileWriteTime.
  (unixSecs + 11644473600'i64) * 10_000_000'i64

proc shapeOutPath(fbxPath: string): string =
  ## "<dir>/<stem>.Shape.Gbx" next to the input, mirroring NadeoImporter naming.
  let (dir, name, _) = splitFile(fbxPath)
  dir / (name & ".Shape.Gbx")

proc writeShapeFor(fbxPath: string, mesh: FbxMesh): int =
  let outPath = shapeOutPath(fbxPath)
  saveShapeGbx(outPath, mesh)
  echo "wrote ", outPath
  return 0

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

  if mode == mShape:
    let (ok, err, m) = loadFbx(path)
    if not ok:
      stderr.writeLine "error: failed to read FBX '" & path & "': " & err
      return 1
    return writeShapeFor(path, m)

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

    # Material binding from the sibling <fbx>.MeshParams.xml (mirroring
    # NadeoImporter); fall back to the stock default if it's absent.
    let (dir, name, _) = splitFile(path)
    let mpPath = dir / (name & ".MeshParams.xml")
    let mats = (if fileExists(mpPath): parseMeshParams(mpPath) else: defaultMaterials())
    echo "  meshparams: ", (if fileExists(mpPath): mpPath else: "(default)")
    for mat in mats:
      echo "    ", mat.name, " -> ", mat.link, " (physics ", mat.physicsId, ")"

    # Emit both the .Shape.Gbx (collision) and the .Mesh.Gbx (render mesh).
    discard writeShapeFor(path, m)
    let meshPath = dir / (name & ".Mesh.Gbx")
    # fileWriteTime is a Windows FILETIME (100ns ticks since 1601); sourceTag mirrors
    # NadeoImporter's embedded source-path string. Both are non-geometric.
    let ft = unixTimeToWinTime(int64(epochTime()))
    let sourceTag = "NadeoImporter Mesh Items\\" & name & ".fbx"
    saveMeshGbx(meshPath, m, mats, ft, sourceTag)
    echo "wrote ", meshPath
    return 0

  stderr.writeLine "nadeo-freeporter: Item import of '" & path &
    "' is not implemented yet."
  return 2

proc main(): int =
  let args = commandLineParams()
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    stdout.write usageText
    return (if args.len == 0: 1 else: 0)

  case args[0].toLowerAscii
  of "mesh", "shape", "item", "gbx":
    if args.len < 2:
      stderr.writeLine "error: '" & args[0] & "' needs a <path>"
      return 1
    let mode = case args[0].toLowerAscii
               of "mesh": mMesh
               of "shape": mShape
               of "item": mItem
               else: mGbx
    return run(mode, args[1])
  else:
    stderr.writeLine "error: unknown command '" & args[0] & "'\n"
    stdout.write usageText
    return 1

when isMainModule:
  quit main()
