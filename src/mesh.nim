## .Mesh.Gbx (CPlugSolid2Model, class/chunk 0x090BB000 version 32) body generation.
##
## The render mesh is a CPlugSolid2Model holding one CPlugVisualIndexedTriangles
## visual whose geometry lives in a CPlugVertexStream (positions + normals + base
## UV + lightmap UV + tangents, all planar arrays), plus an inline CPlugIndexBuffer.
## Layout fully decoded & confirmed byte-identical against NadeoImporter on the
## ladder goldens — see memory `mesh-body-structure` and tests/mesh_probe.nim.
##
## What this generates (verified byte-exact on the 4-fixture ladder):
##  - geometry EXPLODED to 3 unique verts per triangle (NadeoImporter does not share
##    render verts), so indices are the identity 0..3N-1 (delta-encoded i16).
##  - normals/tangents packed Dec3N (round(c*511), 10 bits each).
##  - lightmap UV (TexCoord1): a deterministic grid atlas — G=ceil(sqrt(nTris))
##    columns, pitch 1/G, inset 0.05/G; triangle t fills cell (t mod G, t div G)
##    corner-to-corner as (x0,y0),(x1,y0),(x1,y1).
##  - tangents: UV-gradient when the triangle's UVs are non-degenerate, else a
##    geometric fallback from the normal (ref axis Z, or Y when N points along Z).
##  - bounding box stored as (center, halfSize); PreLightGen carries the lightmap
##    atlas box (min=inset, maxU=1-inset, maxV=rows/G-inset) and scale 10*G/9.
##
## Two fields are input/environment-derived, not geometric: `fileWriteTime` (the
## only thing that varies between two NadeoImporter runs of the same fbx — see
## memory) and `sourceTag` (the U06 source-path string). buildMeshBody takes both
## so a caller can reproduce a golden exactly; the CLI passes live values.
##
## NOT yet general: only flat-shaded explosion + single stock material (the
## customMaterial node + trailing tail are emitted verbatim from the ladder, which
## is constant there); smooth-vertex sharing, arbitrary materials, and the lightmap
## packing of large/again-degenerate meshes need more goldens.

import std/math
import gbx
import ufbx

# 6 vertex DataDecls (Position Float3, Normal Dec3N, TexCoord0/1 Float2,
# TangentU/V Dec3N) — geometry-independent, emitted verbatim.
const dataDecls = [
  0x00'u8, 0x04'u8, 0xA0'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x05'u8, 0x1C'u8, 0xA0'u8, 0x10'u8,
  0x30'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x0C'u8, 0x00'u8, 0x0A'u8, 0x02'u8, 0xA0'u8, 0x20'u8,
  0x40'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x10'u8, 0x00'u8, 0x0B'u8, 0x02'u8, 0xA0'u8, 0x20'u8,
  0x60'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x18'u8, 0x00'u8, 0x12'u8, 0x1C'u8, 0xA0'u8, 0x10'u8,
  0x80'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x20'u8, 0x00'u8, 0x14'u8, 0x1C'u8, 0xA0'u8, 0x10'u8,
  0x90'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x24'u8, 0x00'u8,
]

# Trailing blob from U07 (int 1) to end of body: U07, the customMaterial
# CPlugMaterialUserInst node ("Mat0" -> "PlatformTech"), empty joints / U10..U18,
# and the skippable fake-occlusion chunk 0x090BB002 + final FACADE. Constant across
# the ladder (single stock material), emitted verbatim.
const meshTail = [
  0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x03'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0xD0'u8, 0x0F'u8, 0x09'u8, 0x00'u8, 0xD0'u8, 0x0F'u8, 0x09'u8, 0x0B'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x40'u8, 0x04'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x4D'u8, 0x61'u8, 0x74'u8,
  0x30'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x10'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x40'u8, 0x0C'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x50'u8, 0x6C'u8, 0x61'u8, 0x74'u8, 0x66'u8,
  0x6F'u8, 0x72'u8, 0x6D'u8, 0x54'u8, 0x65'u8, 0x63'u8, 0x68'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x01'u8, 0xD0'u8, 0x0F'u8, 0x09'u8, 0x05'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x80'u8, 0x3F'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x02'u8, 0xD0'u8, 0x0F'u8, 0x09'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0xDE'u8, 0xCA'u8, 0xFA'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x00'u8, 0x00'u8, 0x80'u8, 0x3F'u8, 0x00'u8,
  0x00'u8, 0x80'u8, 0x3F'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x02'u8,
  0xB0'u8, 0x0B'u8, 0x09'u8, 0x50'u8, 0x49'u8, 0x4B'u8, 0x53'u8, 0x08'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0xDE'u8, 0xCA'u8, 0xFA'u8,
]

const matFolder = "Stadium\\Media\\Material\\"

type Vec3 = array[3, float32]

proc sub(a, b: Vec3): Vec3 = [a[0]-b[0], a[1]-b[1], a[2]-b[2]]
proc cross(a, b: Vec3): Vec3 =
  [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]]

proc putDec3N(w: var GbxWriter, v: Vec3) =
  ## Pack a (roughly unit) vector as Dec3N: round(clamp(c,-1,1)*511), 10 bits each,
  ## (z<<20)|(y<<10)|x. Mirrors gbx-net WriteVec3_10b exactly.
  proc q(c: float32): uint32 =
    let cc = max(-1.0'f32, min(1.0'f32, c))
    uint32(int(round(cc * 511.0'f32)) and 0x3FF)
  w.putU32((q(v[2]) shl 20) or (q(v[1]) shl 10) or q(v[0]))

type Tri = tuple[c0, c1, c2: int]   # three corner indices, fan order

proc triangulate(mesh: FbxMesh): seq[Tri] =
  ## Fan-triangulate every face, preserving FBX corner order (= NadeoImporter's
  ## triangle/vertex emission order on these fixtures).
  for f in mesh.faces:
    for k in 1 ..< f.count - 1:
      result.add (f.first, f.first + k, f.first + k + 1)

proc buildMeshBody*(mesh: FbxMesh, fileWriteTime: int64, sourceTag: string): seq[byte] =
  ## Serialize the decompressed CPlugSolid2Model body. `fileWriteTime` and
  ## `sourceTag` are the only non-geometric inputs (pass a golden's values to
  ## reproduce it byte-for-byte; see module doc).
  let tris = triangulate(mesh)
  let nTris = tris.len
  let nVerts = nTris * 3

  proc pos(c: int): Vec3 =
    let p = mesh.cornerPos[c]
    [mesh.positions[p*3], mesh.positions[p*3+1], mesh.positions[p*3+2]]
  proc nrm(c: int): Vec3 =
    [mesh.cornerNormal[c*3], mesh.cornerNormal[c*3+1], mesh.cornerNormal[c*3+2]]
  proc uv(c: int): array[2, float32] = [mesh.cornerUv[c*2], mesh.cornerUv[c*2+1]]
  proc lm(c: int): array[2, float32] = [mesh.cornerUv2[c*2], mesh.cornerUv2[c*2+1]]
  proc tan(c: int): Vec3 =
    [mesh.cornerTangent[c*3], mesh.cornerTangent[c*3+1], mesh.cornerTangent[c*3+2]]
  proc bitan(c: int): Vec3 =
    [mesh.cornerBitangent[c*3], mesh.cornerBitangent[c*3+1], mesh.cornerBitangent[c*3+2]]

  var w = initGbxWriter()
  w.putU32(0x090BB000'u32)        # chunk id
  w.putI32(32)                    # version
  w.putI32(3)                     # Id version (first Id in the body)
  w.putU32(0xFFFFFFFF'u32)        # U01 = empty Id

  # ShadedGeom[1]
  w.putI32(1)
  w.putI32(0); w.putI32(0); w.putI32(-1); w.putI32(1); w.putI32(0)

  # visuals: deprecVersion, count, one node-ref
  w.putI32(10)                    # deprec version
  w.putI32(1)                     # count
  w.putI32(1)                     # node index
  w.putU32(0x0901E000'u32)        # CPlugVisualIndexedTriangles

  # CPlugVisual base chunks
  w.putU32(0x09006001'u32); w.putU32(0xFFFFFFFF'u32)   # id = empty
  w.putU32(0x09006005'u32); w.putI32(0)                # SubVisuals[]
  w.putU32(0x09006009'u32); w.putF32(0.0'f32)          # float
  w.putU32(0x0900600B'u32); w.putI32(0)                # Splits[]

  # CPlugVisual chunk 0x0900600F
  w.putU32(0x0900600F'u32)
  w.putI32(6)                     # version
  w.putU32(0x38'u32)              # flags (raw)
  w.putI32(0)                     # numTexCoordSets (TM2020 uses vertex streams)
  w.putI32(int32(nVerts))         # Count
  w.putI32(1)                     # VertexStreams count
  w.putI32(2)                     # node index
  w.putU32(0x09056000'u32)        # CPlugVertexStream

  # CPlugVertexStream chunk 0x09056000
  w.putU32(0x09056000'u32)
  w.putI32(1)                     # version
  w.putI32(int32(nVerts))         # count
  w.putU32(3'u32)                 # flags
  w.putI32(-1)                    # streamModel ref (null)
  w.putI32(6)                     # DataDecl count
  w.putBytes(dataDecls)
  w.putI32(1)                     # VStream bool

  # Positions
  for t in tris:
    for c in [t.c0, t.c1, t.c2]:
      let p = pos(c)
      w.putF32(p[0]); w.putF32(p[1]); w.putF32(p[2])
  # Normals (Dec3N)
  for t in tris:
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(nrm(c))
  # TexCoord0 (authored UV)
  for t in tris:
    for c in [t.c0, t.c1, t.c2]:
      let a = uv(c); w.putF32(a[0]); w.putF32(a[1])
  # TexCoord1 (lightmap UV) — passthrough from the FBX 2nd UV set (the Blender
  # exporter generates the per-face lightmap atlas; NadeoImporter just copies it).
  for t in tris:
    for c in [t.c0, t.c1, t.c2]:
      let a = lm(c); w.putF32(a[0]); w.putF32(a[1])
  # TangentU/TangentV (Dec3N) — passthrough of the FBX tangent frame (use_tspace).
  for t in tris:
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(tan(c))
  for t in tris:
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(bitan(c))
  w.putU32(0xFACADE01'u32)        # end CPlugVertexStream node

  # Bounding box (center, halfSize) over all emitted positions.
  var lo = pos(tris[0].c0); var hi = lo
  for t in tris:
    for c in [t.c0, t.c1, t.c2]:
      let p = pos(c)
      for a in 0 .. 2:
        if p[a] < lo[a]: lo[a] = p[a]
        if p[a] > hi[a]: hi[a] = p[a]
  for a in 0 .. 2: w.putF32((lo[a] + hi[a]) * 0.5'f32)   # center
  for a in 0 .. 2: w.putF32((hi[a] - lo[a]) * 0.5'f32)   # half size

  w.putI32(0)                     # BitmapElemToPack[]
  w.putI32(0)                     # UvGroups[]
  w.putI32(0); w.putI32(0)        # 0x0900600F U02, U03

  # remaining visual-node chunks
  w.putU32(0x09006010'u32); w.putI32(0); w.putI32(0)     # version, MorphCount
  w.putU32(0x0902C002'u32); w.putI32(-1)                 # CMwNod ref
  w.putU32(0x0902C004'u32); w.putI32(0); w.putI32(0)     # tangent counts
  w.putU32(0x0906A001'u32); w.putI32(1)                  # hasIndexBuffer
  # inline CPlugIndexBuffer (no index/classId), chunk 0x09057001
  w.putU32(0x09057001'u32)
  w.putI32(2)                     # Flags
  w.putI32(int32(nVerts))         # index count
  w.putU16(0'u16)                 # delta-encoded i16: first = 0
  for _ in 1 ..< nVerts: w.putU16(1'u16)
  w.putU32(0xFACADE01'u32)        # end index-buffer node
  w.putU32(0xFACADE01'u32)        # end visual node

  # outer tail
  w.putI32(0)                     # materialIds[]
  w.putI32(1)                     # customMaterials count
  w.putI32(-1)                    # skel ref (null)
  w.putI32(0)                     # lodMaxDistAtFov90[]
  w.putI32(1)                     # visCstType
  w.putI32(1)                     # hasPreLightGen
  # PreLightGen lightmap scale = sqrt(totalWorldArea / totalLightmapUvArea), i.e.
  # texel density: world surface area vs the area the atlas gives it. Each tri's
  # lightmap area is half a usable cell = 0.5*(0.9/G)^2.
  # PreLightGen scale = sqrt(totalWorldArea / totalLightmapUvArea). uvArea is
  # SUMMED per triangle as 0.5*(c1.u-c0.u)*(c2.v-c0.v) over the passthrough
  # lightmap UVs (the per-face atlas lays each triangle as a right triangle
  # bl,br,tr) — the accumulation order is load-bearing for the float32 ULP.
  var worldArea = 0.0'f32
  var uvArea = 0.0'f32
  var lmMin = lm(tris[0].c0)
  var lmMax = lmMin
  for t in tris:
    let cr = cross(sub(pos(t.c1), pos(t.c0)), sub(pos(t.c2), pos(t.c0)))
    worldArea += 0.5'f32 * sqrt(cr[0]*cr[0] + cr[1]*cr[1] + cr[2]*cr[2])
    let a = lm(t.c0); let b = lm(t.c1); let c = lm(t.c2)
    uvArea += 0.5'f32 * (b[0] - a[0]) * (c[1] - a[1])
    for cc in [t.c0, t.c1, t.c2]:
      let u = lm(cc)
      for k in 0 .. 1:
        if u[k] < lmMin[k]: lmMin[k] = u[k]
        if u[k] > lmMax[k]: lmMax[k] = u[k]
  let plgScale = sqrt(worldArea / uvArea)
  # PreLightGen
  w.putI32(1)                     # version
  w.putI32(1)                     # int
  w.putF32(plgScale)              # lightmap scale
  w.putI32(1)                     # bool
  w.putF32(lmMin[0]); w.putF32(lmMin[1])     # atlas box min (lightmap UV bounds)
  w.putF32(lmMax[0]); w.putF32(lmMax[1])     # atlas box max
  w.putU32(0x7F7FFFFF'u32); w.putU32(0x7F7FFFFF'u32)     # +FLT_MAX, +FLT_MAX
  w.putU32(0xFF7FFFFF'u32); w.putU32(0xFF7FFFFF'u32)     # -FLT_MAX, -FLT_MAX
  w.putI32(0); w.putI32(0)        # spriteCount
  w.putI32(0)                     # boxaligned[]
  w.putI32(0)                     # uvGroups[]

  w.putI64(fileWriteTime)
  w.putStr("")                    # U03
  w.putStr(matFolder)             # materialsFolderName
  w.putStr("")                    # U04
  w.putI32(0)                     # lights[]
  w.putI32(0)                     # lightUserModels[]
  w.putI32(0)                     # lightInsts[]
  w.putI32(0)                     # damageZone
  w.putU32(0)                     # flags
  w.putI32(1)                     # U05
  w.putStr(sourceTag)             # U06 (source path)
  w.putBytes(meshTail)            # U07 .. end (constant)
  result = w.buf

# Header user data: one header chunk descriptor (chunk 0x090BB000), constant
# across the ladder goldens — emitted verbatim.
const meshUserData = @[
  0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0xB0'u8, 0x0B'u8, 0x09'u8,
  0x04'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x05'u8, 0x00'u8, 0x00'u8, 0x00'u8,
]

proc meshInfo*(): GbxInfo =
  ## Header/framing for a .Mesh.Gbx, matching the NadeoImporter goldens: GBX v6,
  ## binary, uncompressed ref table, LZO body, CPlugSolid2Model, 16-byte header
  ## user data, 4 nodes. Header bytes are byte-identical to the goldens.
  GbxInfo(
    version: 6,
    format: 'B',
    refTableCompression: gcUncompressed,
    bodyCompression: gcCompressed,
    unknownByte: 'R',
    classId: 0x090BB000'u32,
    userDataLen: 16,
    userData: meshUserData,
    numNodes: 4,
    numExternalNodes: 0)

proc buildMeshGbx*(mesh: FbxMesh, fileWriteTime: int64, sourceTag: string): seq[byte] =
  ## Full .Mesh.Gbx file bytes (header + framing + LZO-compressed body). The LZO
  ## bytes differ from Nadeo's (LZO1X-1 vs -999) but decompress to the byte-identical
  ## body; the game reads the decompressed content. See [[shape-body-solved]].
  writeGbx(meshInfo(), buildMeshBody(mesh, fileWriteTime, sourceTag))

proc saveMeshGbx*(path: string, mesh: FbxMesh, fileWriteTime: int64, sourceTag: string) =
  saveGbx(path, meshInfo(), buildMeshBody(mesh, fileWriteTime, sourceTag))
