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

const usageText = """
nadeo-freeporter — Linux mesh -> TM2020 .Item.Gbx importer

usage:
  nadeo-freeporter mesh <path>     build a .Mesh.Gbx from a mesh file
  nadeo-freeporter item <path>     build a .Item.Gbx from a mesh file
  nadeo-freeporter --help          show this help

(scaffold: argument dispatch only; import pipeline not yet wired)
"""

type Mode = enum mMesh, mItem

proc run(mode: Mode, path: string): int =
  if not fileExists(path):
    stderr.writeLine "error: file not found: " & path
    return 1

  if mode == mMesh:
    # Front-end smoke test: parse the FBX via ufbx and report what we found.
    # (The .Mesh.Gbx / .Shape.Gbx writers are not wired yet.)
    let s = summarizeFbx(path)
    if s.ok == 0:
      stderr.writeLine "error: failed to read FBX '" & path & "': " & s.errorMsg
      return 1
    echo "FBX: ", path
    echo "  meshes:    ", s.meshes
    echo "  materials: ", s.materials
    echo "  vertices:  ", s.vertices
    echo "  faces:     ", s.faces
    echo "  triangles: ", s.triangles
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
  of "mesh", "item":
    if args.len < 2:
      stderr.writeLine "error: '" & args[0] & "' needs a <path>"
      return 1
    let mode = (if args[0].toLowerAscii == "mesh": mMesh else: mItem)
    return run(mode, args[1])
  else:
    stderr.writeLine "error: unknown command '" & args[0] & "'\n"
    stdout.write usageText
    return 1

when isMainModule:
  quit main()
