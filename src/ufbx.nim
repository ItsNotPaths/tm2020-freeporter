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

# --- Full geometry extraction ------------------------------------------------
# The C shim returns one heap object with flat arrays (see ufbx_bridge.h). We
# mirror it as a raw `ptr`, copy everything into ordinary Nim seqs, then free
# the C side — so callers never touch raw pointers or manual frees.

type
  FbxMeshC {.importc: "fp_fbx_mesh", header: "ufbx_bridge.h".} = object
    ok: cint
    error: array[512, cchar]
    num_positions: csize_t
    positions: ptr UncheckedArray[cfloat]
    num_corners: csize_t
    corner_position: ptr UncheckedArray[uint32]
    corner_normal: ptr UncheckedArray[cfloat]
    corner_uv: ptr UncheckedArray[cfloat]
    corner_uv2: ptr UncheckedArray[cfloat]
    corner_tangent: ptr UncheckedArray[cfloat]
    corner_bitangent: ptr UncheckedArray[cfloat]
    num_faces: csize_t
    face_first: ptr UncheckedArray[uint32]
    face_count: ptr UncheckedArray[uint32]
    face_material: ptr UncheckedArray[uint32]
    num_materials: csize_t
    material_names: ptr UncheckedArray[cstring]

proc fp_fbx_load(path: cstring): ptr FbxMeshC {.importc, header: "ufbx_bridge.h".}
proc fp_fbx_free(m: ptr FbxMeshC) {.importc, header: "ufbx_bridge.h".}

type
  FbxFace* = object
    ## One polygon: `count` corners starting at `first` in the corner arrays,
    ## using material `material` (index into `FbxMesh.materials`).
    first*, count*, material*: int
  FbxMesh* = object
    ## Whole-scene geometry, merged into one vertex/face soup. `positions` are
    ## unique control points (x,y,z triples). A "corner" is one face-vertex;
    ## `cornerPos` indexes `positions`, `cornerNormal`/`cornerUv` are per-corner.
    positions*: seq[float32]      # 3 per position
    cornerPos*: seq[int]          # 1 per corner -> index into positions
    cornerNormal*: seq[float32]   # 3 per corner
    cornerUv*: seq[float32]       # 2 per corner (UV set 0 / base material)
    cornerUv2*: seq[float32]      # 2 per corner (UV set 1 / lightmap)
    cornerTangent*: seq[float32]  # 3 per corner (UV set 0 tangent)
    cornerBitangent*: seq[float32] # 3 per corner (UV set 0 bitangent)
    faces*: seq[FbxFace]
    materials*: seq[string]

proc loadFbx*(path: string): tuple[ok: bool, error: string, mesh: FbxMesh] =
  ## Parse an FBX and copy its geometry into Nim seqs. The C scene is freed
  ## before returning, so the result owns all its data.
  let c = fp_fbx_load(path.cstring)
  if c == nil:
    return (false, "out of memory loading FBX", FbxMesh())
  defer: fp_fbx_free(c)

  if c.ok == 0:
    var msg = ""
    for ch in c.error:
      if ch == '\0': break
      msg.add char(ch)
    return (false, msg, FbxMesh())

  var m = FbxMesh()

  let np = int(c.num_positions)
  m.positions = newSeq[float32](np * 3)
  for i in 0 ..< np * 3: m.positions[i] = float32(c.positions[i])

  let nc = int(c.num_corners)
  m.cornerPos = newSeq[int](nc)
  m.cornerNormal = newSeq[float32](nc * 3)
  m.cornerUv = newSeq[float32](nc * 2)
  m.cornerUv2 = newSeq[float32](nc * 2)
  m.cornerTangent = newSeq[float32](nc * 3)
  m.cornerBitangent = newSeq[float32](nc * 3)
  for i in 0 ..< nc: m.cornerPos[i] = int(c.corner_position[i])
  for i in 0 ..< nc * 3:
    m.cornerNormal[i] = float32(c.corner_normal[i])
    m.cornerTangent[i] = float32(c.corner_tangent[i])
    m.cornerBitangent[i] = float32(c.corner_bitangent[i])
  for i in 0 ..< nc * 2:
    m.cornerUv[i] = float32(c.corner_uv[i])
    m.cornerUv2[i] = float32(c.corner_uv2[i])

  let nf = int(c.num_faces)
  m.faces = newSeq[FbxFace](nf)
  for i in 0 ..< nf:
    m.faces[i] = FbxFace(
      first: int(c.face_first[i]),
      count: int(c.face_count[i]),
      material: int(c.face_material[i]))

  let nm = int(c.num_materials)
  m.materials = newSeq[string](nm)
  for i in 0 ..< nm:
    m.materials[i] = (if c.material_names[i] != nil: $c.material_names[i] else: "")

  result = (true, "", m)
