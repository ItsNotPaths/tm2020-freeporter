## FBX front-end — a thin Nim FFI to the C shim in ufbx_bridge.c (which wraps
## the vendored ufbx parser). We deliberately bind only the shim's flat structs
## and procs, never ufbx's own headers, so the Nim stays simple. The shim and
## ufbx.c are compiled straight into the binary; no shared library.

import std/os

const
  ufbxDir = currentSourcePath().parentDir().parentDir() / "vendor" / "ufbx"
  srcDir  = currentSourcePath().parentDir()

{.passC: "-I" & ufbxDir.}
{.passC: "-I" & srcDir.}
{.compile: ufbxDir / "ufbx.c".}
{.compile: srcDir / "ufbx_bridge.c".}
{.passL: "-lm".}

type
  FbxSummary* {.bycopy, importc: "fp_fbx_summary", header: "ufbx_bridge.h".} = object
    ok*: cint
    meshes*: csize_t
    materials*: csize_t
    vertices*: csize_t
    faces*: csize_t
    triangles*: csize_t
    error*: array[512, cchar]

proc fp_fbx_summarize(path: cstring): FbxSummary
  {.importc, header: "ufbx_bridge.h".}

proc summarizeFbx*(path: string): FbxSummary =
  ## Load an FBX and report mesh/material/vertex/face/triangle counts.
  fp_fbx_summarize(path.cstring)

proc errorMsg*(s: FbxSummary): string =
  ## Decode the shim's NUL-terminated char[512] into a Nim string.
  result = ""
  for c in s.error:
    if c == '\0': break
    result.add char(c)
