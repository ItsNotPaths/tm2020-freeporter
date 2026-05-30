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
import materials

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

proc writeId(w: var GbxWriter, s: string) =
  ## Lookback-string write: empty -> 0xFFFFFFFF; otherwise a fresh local name
  ## (flag 0x40000000 + the string). All our material Names/Links are distinct, so
  ## we never emit back-references (would need dict tracking — see materials note).
  if s.len == 0: w.putU32(0xFFFFFFFF'u32)
  else: (w.putU32(0x40000000'u32); w.putStr(s))

proc writeMaterialNode(w: var GbxWriter, m: MeshMaterial, nodeIndex: int32) =
  ## One customMaterials entry: the Material archive (empty name) then an inline
  ## CPlugMaterialUserInst node-ref (chunks 0x090FD000/001/002). All fields constant
  ## except MaterialName, SurfacePhysicId, SurfaceGameplayId, Link.
  w.putStr("")                      # Material.MaterialName (empty -> inst follows)
  w.putI32(nodeIndex)               # node-ref index
  w.putU32(0x090FD000'u32)          # CPlugMaterialUserInst class id
  # chunk 0x090FD000 (v11)
  w.putU32(0x090FD000'u32)
  w.putI32(11)                      # version
  w.putU8(0)                        # IsUsingGameMaterial (boolbyte)
  w.writeId(m.name)                 # MaterialName
  w.writeId("")                     # Model
  w.putStr("")                      # BaseTexture
  w.putU8(m.physicsId)              # SurfacePhysicId
  w.putU8(m.gameplayId)             # SurfaceGameplayId
  w.writeId(m.link)                 # Link
  w.putI32(0); w.putI32(0); w.putI32(0); w.putI32(0); w.putI32(0)  # Csts/Color/UvAnims/ids/UserTextures
  w.writeId("")                     # HidingGroup
  # chunk 0x090FD001 (v5)
  w.putU32(0x090FD001'u32)
  w.putI32(5)                       # version
  w.putI32(-1)                      # bitmapAtlas ref (null)
  w.putI32(0)                       # TilingU
  w.putI32(0)                       # TilingV
  w.putF32(1.0'f32)                 # TextureSizeInMeters
  w.putI32(0)                       # u01
  w.putI32(0)                       # IsNatural (i32 bool)
  # chunk 0x090FD002
  w.putU32(0x090FD002'u32)
  w.putI32(0); w.putI32(0)          # version, int
  w.putU32(0xFACADE01'u32)          # end inst node

type Tri = tuple[c0, c1, c2: int]   # three corner indices, fan order
type Group = tuple[mat: int, tris: seq[Tri]]   # one material's triangles

proc triGroups*(mesh: FbxMesh): seq[Group] =
  ## Fan-triangulate every face, GROUPED BY material slot (ascending, non-empty),
  ## preserving FBX face order within a group. NadeoImporter emits one visual per
  ## material this way (confirmed by fixture 13). Single-material meshes -> 1 group
  ## holding all triangles in face order.
  var maxMat = 0
  for f in mesh.faces:
    if f.material > maxMat: maxMat = f.material
  for slot in 0 .. maxMat:
    var ts: seq[Tri] = @[]
    for f in mesh.faces:
      if f.material == slot:
        for k in 1 ..< f.count - 1:
          ts.add (f.first, f.first + k, f.first + k + 1)
    if ts.len > 0: result.add (slot, ts)

proc writeVisual(w: var GbxWriter, mesh: FbxMesh, tris: seq[Tri], nodeIndex: int32) =
  ## Emit one CPlugVisualIndexedTriangles node-ref (+ its CPlugVertexStream and
  ## inline CPlugIndexBuffer) for `tris`. The vertex stream is node `nodeIndex+1`.
  ## All vertex attributes are passthrough; verts are exploded (3 per triangle),
  ## indices the identity 0..3k-1. See module doc.
  let nVerts = tris.len * 3
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

  w.putI32(nodeIndex)             # visual node index
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
  w.putI32(nodeIndex + 1)         # vertex-stream node index
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
  for t in tris:                  # Positions
    for c in [t.c0, t.c1, t.c2]:
      let p = pos(c); w.putF32(p[0]); w.putF32(p[1]); w.putF32(p[2])
  for t in tris:                  # Normals (Dec3N)
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(nrm(c))
  for t in tris:                  # TexCoord0 (authored UV)
    for c in [t.c0, t.c1, t.c2]:
      let a = uv(c); w.putF32(a[0]); w.putF32(a[1])
  for t in tris:                  # TexCoord1 (lightmap UV, passthrough)
    for c in [t.c0, t.c1, t.c2]:
      let a = lm(c); w.putF32(a[0]); w.putF32(a[1])
  for t in tris:                  # TangentU (Dec3N, passthrough)
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(tan(c))
  for t in tris:                  # TangentV (Dec3N, passthrough)
    for c in [t.c0, t.c1, t.c2]: w.putDec3N(bitan(c))
  w.putU32(0xFACADE01'u32)        # end CPlugVertexStream node
  # Bounding box (center, halfSize) over this group's positions.
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
  w.putU32(0x09057001'u32)        # inline CPlugIndexBuffer chunk
  w.putI32(2)                     # Flags
  w.putI32(int32(nVerts))         # index count
  w.putU16(0'u16)                 # delta-encoded i16: first = 0
  for _ in 1 ..< nVerts: w.putU16(1'u16)
  w.putU32(0xFACADE01'u32)        # end index-buffer node
  w.putU32(0xFACADE01'u32)        # end visual node

proc buildMeshBody*(mesh: FbxMesh, materials: seq[MeshMaterial],
                    fileWriteTime: int64, sourceTag: string,
                    nodeBase: int = 0, emitIdVersion: bool = true): seq[byte] =
  ## Serialize the decompressed CPlugSolid2Model body. `materials` is the parsed
  ## MeshParams binding (Name/Link/PhysicsId). `fileWriteTime` and `sourceTag` are
  ## the only non-geometric inputs (pass a golden's values to reproduce it
  ## byte-for-byte; see module doc). Multiple materials are emitted as one visual +
  ## vertex stream per material group, N ShadedGeoms and N CPlugMaterialUserInst
  ## nodes (PreLightGen stays model-level over all triangles).
  ##
  ## `nodeBase` shifts every emitted node-ref index, for when this body is embedded
  ## as a sub-node (the .Item.Gbx embeds the mesh as node 3, so nodeBase=3). All Id
  ## writes are fresh strings (position-independent), so the only other embedding
  ## concern is the Id-version int: it is written once per *decompressed body*, so
  ## set `emitIdVersion=false` when an enclosing writer already emitted it.
  let groups = triGroups(mesh)
  doAssert groups.len > 0, "mesh has no triangles"
  let n = groups.len

  # Resolve each group's material (by FBX material name) from the MeshParams binding.
  proc materialFor(slot: int): MeshMaterial =
    let nm = mesh.materials[slot]
    for mm in materials:
      if mm.name == nm: return mm
    raise newException(ValueError, "no MeshParams material named '" & nm & "'")

  # Accessors for the model-level PreLightGen (aggregated over ALL triangles).
  proc pos(c: int): Vec3 =
    let p = mesh.cornerPos[c]
    [mesh.positions[p*3], mesh.positions[p*3+1], mesh.positions[p*3+2]]
  proc lm(c: int): array[2, float32] = [mesh.cornerUv2[c*2], mesh.cornerUv2[c*2+1]]

  var w = initGbxWriter()
  w.putU32(0x090BB000'u32)        # chunk id
  w.putI32(32)                    # version
  if emitIdVersion: w.putI32(3)   # Id version (only if first Id in the body)
  w.putU32(0xFFFFFFFF'u32)        # U01 = empty Id

  # ShadedGeom[n]: one per material group (visualIndex g, materialIndex g).
  w.putI32(int32(n))
  for g in 0 ..< n:
    w.putI32(int32(g)); w.putI32(int32(g)); w.putI32(-1); w.putI32(1); w.putI32(0)

  # visuals: deprecVersion, count, then one visual per group. Node indices:
  # visual g = 1+2*g, its vertex stream = 2+2*g (index buffers are inline).
  w.putI32(10)                    # deprec version
  w.putI32(int32(n))              # count
  for g in 0 ..< n:
    w.writeVisual(mesh, groups[g].tris, int32(nodeBase + 1 + 2*g))

  # outer tail
  w.putI32(0)                     # materialIds[]
  w.putI32(int32(n))              # customMaterials count
  w.putI32(-1)                    # skel ref (null)
  w.putI32(0)                     # lodMaxDistAtFov90[]
  w.putI32(1)                     # visCstType
  w.putI32(1)                     # hasPreLightGen
  # PreLightGen (model level): scale = sqrt(worldArea / uvArea) and the atlas box,
  # aggregated over EVERY triangle across all groups. uvArea is summed per triangle
  # as 0.5*(c1.u-c0.u)*(c2.v-c0.v) over the passthrough lightmap UVs (right-triangle
  # cells); the accumulation order is load-bearing for the float32 ULP.
  var worldArea = 0.0'f32
  var uvArea = 0.0'f32
  var lmMin = lm(groups[0].tris[0].c0)
  var lmMax = lmMin
  for grp in groups:
    for t in grp.tris:
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
  w.putI32(1)                     # U07
  # customMaterials: one CPlugMaterialUserInst per group, node index 1+2*n+g.
  for g in 0 ..< n:
    w.writeMaterialNode(materialFor(groups[g].mat), int32(nodeBase + 1 + 2*n + g))
  # constant model tail: joints[], U10-U13, U14 ref(null), U15/U16=1.0, U17 id,
  # U18, then the skippable fake-occlusion chunk 0x090BB002 (empty) + node FACADE.
  w.putI32(0)                     # joints[]
  w.putI32(0)                     # U10[]
  w.putI32(0)                     # U11
  w.putI32(0)                     # U12[]
  w.putI32(0)                     # U13
  w.putI32(-1)                    # U14 ref (null)
  w.putF32(1.0'f32)               # U15
  w.putF32(1.0'f32)               # U16
  w.writeId("")                   # U17
  w.putI32(0)                     # U18
  w.putU32(0x090BB002'u32)        # skippable fake-occlusion chunk
  w.putU32(0x534B4950'u32)        # "SKIP"
  w.putI32(8)                     # chunk size
  w.putI32(0); w.putI32(0)        # FileImageBytes len 0 + FakeOccProjs count 0
  w.putU32(0xFACADE01'u32)        # end CPlugSolid2Model node
  result = w.buf

# Header user data: one header chunk descriptor (chunk 0x090BB000), constant
# across the ladder goldens — emitted verbatim.
const meshUserData = @[
  0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0xB0'u8, 0x0B'u8, 0x09'u8,
  0x04'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x05'u8, 0x00'u8, 0x00'u8, 0x00'u8,
]

proc meshNodeCount*(mesh: FbxMesh): int =
  ## Total GBX nodes: the model (1) + one visual + one vertex stream + one material
  ## node per material group = 1 + 3*N. Index buffers are inline (not counted).
  1 + 3 * triGroups(mesh).len

proc meshInfo*(numNodes: int): GbxInfo =
  ## Header/framing for a .Mesh.Gbx, matching the NadeoImporter goldens: GBX v6,
  ## binary, uncompressed ref table, LZO body, CPlugSolid2Model, 16-byte header
  ## user data. `numNodes` = meshNodeCount(mesh). Header bytes are byte-identical.
  GbxInfo(
    version: 6,
    format: 'B',
    refTableCompression: gcUncompressed,
    bodyCompression: gcCompressed,
    unknownByte: 'R',
    classId: 0x090BB000'u32,
    userDataLen: 16,
    userData: meshUserData,
    numNodes: numNodes,
    numExternalNodes: 0)

proc buildMeshGbx*(mesh: FbxMesh, materials: seq[MeshMaterial],
                   fileWriteTime: int64, sourceTag: string): seq[byte] =
  ## Full .Mesh.Gbx file bytes (header + framing + LZO-compressed body). The LZO
  ## bytes differ from Nadeo's (LZO1X-1 vs -999) but decompress to the byte-identical
  ## body; the game reads the decompressed content. See [[shape-body-solved]].
  writeGbx(meshInfo(meshNodeCount(mesh)),
           buildMeshBody(mesh, materials, fileWriteTime, sourceTag))

proc saveMeshGbx*(path: string, mesh: FbxMesh, materials: seq[MeshMaterial],
                  fileWriteTime: int64, sourceTag: string) =
  saveGbx(path, meshInfo(meshNodeCount(mesh)),
          buildMeshBody(mesh, materials, fileWriteTime, sourceTag))
