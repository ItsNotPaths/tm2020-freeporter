## .Item.Gbx (CGameItemModel, class 0x2E002000) generation.
##
## The Item is a catalog wrapper around the already-solved mesh: a CGameItemModel
## (inheriting CGameCtnCollector for name/author/collection/icon metadata) whose
## modern descriptor chunk 0x2E002019 carries an entityModel node-ref ->
##   CGameCommonItemEntityModel (0x2E027000) whose chunk holds a StaticObject ->
##     CPlugStaticObjectModel (0x09159000), an inline archive embedding our
##       CPlugSolid2Model mesh (buildMeshBody) with IsMeshCollidable = true
##       (so the mesh itself is the collision; NO separate CPlugSurface is embedded).
##
## Node layout (numNodes = 5 + 3*N for N material groups):
##   0 CGameItemModel  1 CGameCommonItemEntityModel  2 CPlugStaticObjectModel
##   3 CPlugSolid2Model (mesh, nodeBase=3)  4..(3+3N) visual/vstream/matInst per group
##   (4+3N) CGameItemPlacementParam (DefaultPlacement)
##
## Decoded byte-for-byte against NadeoImporter on the 13-fixture ladder
## (tests/item_probe.nim, tests/item_bytediff.nim). All the wrapper metadata is
## constant except Name (from filename), Author + Collection (from .Item.xml), and
## the two non-geometric mesh fields (fileWriteTime, the U06 source-path string),
## which are passed through to the embedded buildMeshBody.

import gbx
import ufbx
import materials
import mesh

const FACADE = 0xFACADE01'u32

# Stadium is collection index 26 in TM2020 (written as an Id literal, not a string).
proc collectionId(name: string): uint32 =
  case name
  of "Stadium": 26'u32
  else: raise newException(ValueError, "unknown collection '" & name & "'")

proc putIdEmpty(w: var GbxWriter) = w.putU32(0xFFFFFFFF'u32)
proc putIdString(w: var GbxWriter, s: string) =
  ## Fresh lookback string (flag 0x40000000 + the string). Position-independent:
  ## the reader assigns the next index, so we never need back-references here.
  if s.len == 0: w.putIdEmpty()
  else: (w.putU32(0x40000000'u32); w.putStr(s))
proc putIdLiteral(w: var GbxWriter, v: uint32) = w.putU32(v)

# --- Skippable chunk payloads, constant across the ladder (captured verbatim) ---
# CGameItemPlacementParam (node DefaultPlacement) chunk chain.
# 50B: version(0) + short Flags(=1) + CubeCenter/CubeSize/grid-snap/fly/pivot (0).
const placement2E020000 = block:
  var b = newSeq[byte](50); b[4] = 1; b
const placement2E020001 = newSeq[byte](8)           # empty PivotPositions/Rotations arrays
const placement2E020003 = @[                         # PlacementClass (v3) + accel struct
  0x03'u8,0,0,0, 0x0A,0,0,0, 0xFF,0xFF,0xFF,0xFF, 0,0,0,0, 0,0,0,0, 0x01,0,0,0,
  0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0x80,0x3F, 0,0,0,0, 0,0,0,0]
const placement2E020004 = newSeq[byte](8)

proc putSkippable(w: var GbxWriter, chunkId: uint32, payload: openArray[byte]) =
  w.putU32(chunkId)
  w.putU32(0x534B4950'u32)          # skippable marker ("PIKS" on disk)
  w.putI32(int32(payload.len))
  w.putBytes(payload)

proc putIso4Identity(w: var GbxWriter) =
  const m = [1f,0,0, 0,1,0, 0,0,1, 0,0,0]
  for x in m: w.putF32(x)

proc buildItemBody*(mesh: FbxMesh, materials: seq[MeshMaterial],
                    name, author, collection: string,
                    fileWriteTime: int64, sourceTag: string): seq[byte] =
  ## Serialize the decompressed CGameItemModel body. `name` is the item name
  ## (the FBX/Item.xml stem), `author`/`collection` from the .Item.xml. The mesh
  ## subtree is buildMeshBody with nodeBase=3 (and emitIdVersion=false, since the
  ## wrapper already opened the body's shared Id table).
  let nGroups = triGroups(mesh).len
  var w = initGbxWriter()

  # --- CGameCtnCollector metadata chunks ---
  # 0x2E001009: pageName, hasIconFid, parentCollectorId. First body Id -> version 3.
  w.putU32(0x2E001009'u32)
  w.putStr("Items")                 # pageName
  w.putI32(0)                       # hasIconFid (bool) = false
  w.putI32(3)                       # Id version (first Id in the body)
  w.putIdEmpty()                    # parentCollectorId
  # 0x2E00100B: ident {id, collection, author}
  w.putU32(0x2E00100B'u32)
  w.putIdEmpty()                    # id
  w.putIdLiteral(collectionId(collection))
  w.putIdString(author)
  # 0x2E00100C: Name
  w.putU32(0x2E00100C'u32); w.putStr(name)
  # 0x2E00100D: Description
  w.putU32(0x2E00100D'u32); w.putStr("No Description")
  # 0x2E001010: default skin
  w.putU32(0x2E001010'u32)
  w.putI32(3)                       # version
  w.putI32(-1)                      # DefaultSkin ref (null)
  w.putStr("")                      # SkinDirectory
  w.putI32(-1)                      # CMwNod ref (null)
  # 0x2E001011: internal/advanced/catalogPos/prodState
  w.putU32(0x2E001011'u32)
  w.putI32(1)                       # version
  w.putI32(0)                       # IsInternal
  w.putI32(0)                       # IsAdvanced
  w.putI32(1)                       # CatalogPosition
  w.putU8(3)                        # ProdState (Release)
  # 0x2E001012: TM2020 4 ints
  w.putU32(0x2E001012'u32)
  w.putI32(0); w.putI32(1); w.putI32(0); w.putI32(0)

  # --- CGameItemModel chunks ---
  # 0x2E002008: NadeoSkinFids (7 null)
  w.putU32(0x2E002008'u32); w.putI32(7)
  for _ in 0 ..< 7: w.putI32(-1)
  # 0x2E002009: Cameras (deprecVersion 10, count 0)
  w.putU32(0x2E002009'u32); w.putI32(10); w.putI32(0)
  # 0x2E00200C: RaceInterfaceFid (null)
  w.putU32(0x2E00200C'u32); w.putI32(-1)
  # 0x2E002012: ground/orbital floats
  w.putU32(0x2E002012'u32)
  w.putF32(0); w.putF32(0); w.putF32(0)   # GroundPoint
  w.putF32(0)                              # PainterGroundMargin
  w.putF32(0)                              # OrbitalCenterHeightFromGround
  w.putF32(-1.0'f32)                       # OrbitalRadiusBase
  w.putF32(0.15'f32)                       # OrbitalPreviewAngle
  # 0x2E002015: ItemTypeE = 1 (Ornament/StaticObject)
  w.putU32(0x2E002015'u32); w.putI32(1)

  # 0x2E002019: modern descriptor (version 15)
  w.putU32(0x2E002019'u32)
  w.putI32(15)                      # Version
  w.putIdEmpty()                    # defaultWeaponName
  w.putI32(-1)                      # phyModelCustom
  w.putI32(-1)                      # visModelCustom
  w.putI32(0)                       # actions[]
  w.putI32(0)                       # defaultCam (None)
  w.putI32(-1)                      # entityModelEdition (null) -> entityModel follows
  # entityModel node-ref -> CGameCommonItemEntityModel (node 1)
  w.putI32(1); w.putU32(0x2E027000'u32)
  w.putU32(0x2E027000'u32)          # entity chunk
  w.putI32(4)                       # entity version
  # StaticObject node-ref -> CPlugStaticObjectModel (node 2)
  w.putI32(2); w.putU32(0x09159000'u32)
  w.putI32(3)                       # CPlugStaticObjectModel archive version
  # Mesh node-ref -> CPlugSolid2Model (node 3) + the embedded mesh body
  w.putI32(3); w.putU32(0x090BB000'u32)
  w.putBytes(buildMeshBody(mesh, materials, fileWriteTime, sourceTag,
                           nodeBase = 3, emitIdVersion = false))
  w.putU8(1)                        # IsMeshCollidable = true (no separate Shape)
  # entity v2+ tail
  w.putI32(-1)                      # TriggerShape
  w.putIso4Identity()               # iso4
  w.putI32(-1)                      # ParticleEmitter
  w.putI32(0)                       # ActionModels[]
  w.putI32(-1)                      # CMwNod (v<=5)
  w.putStr(""); w.putStr(""); w.putStr(""); w.putStr(""); w.putStr("")
  w.putIso4Identity()               # iso4
  w.putI32(0)                       # ExprValidator
  w.putU32(FACADE)                  # end CGameCommonItemEntityModel node
  # back in 0x2E002019 (version >= 13/15)
  w.putI32(-1)                      # vfx
  w.putI32(-1)                      # materialModifier

  # 0x2E00201A: CMwNod (null)
  w.putU32(0x2E00201A'u32); w.putI32(-1)
  # 0x2E00201C: default placement (version 5) -> CGameItemPlacementParam node
  let placementNode = int32(4 + 3 * nGroups)
  w.putU32(0x2E00201C'u32); w.putI32(5)
  w.putI32(placementNode); w.putU32(0x2E020000'u32)
  w.putSkippable(0x2E020000'u32, placement2E020000)
  w.putSkippable(0x2E020001'u32, placement2E020001)
  w.putSkippable(0x2E020003'u32, placement2E020003)
  w.putSkippable(0x2E020004'u32, placement2E020004)
  w.putU32(FACADE)                  # end CGameItemPlacementParam node
  # 0x2E00201E: archetype (version 7)
  w.putU32(0x2E00201E'u32)
  w.putI32(7)
  w.putStr("")                      # ArchetypeRef
  w.putI32(-1)                      # ArchetypeFid (null)
  w.putStr("")                      # SkinDirNameCustom
  w.putI32(-1)                      # int(-1)
  # 0x2E00201F: waypoint / lightmap (version 12)
  w.putU32(0x2E00201F'u32)
  w.putI32(12)                      # version
  w.putI32(3)                       # WaypointType (None)
  w.putI32(0)                       # DisableLightmap (bool)
  w.putI32(-1)                      # CMwNod (v<=12)
  w.putU8(1)                        # byte
  w.putI32(-1); w.putI32(-1)        # int, int
  # 0x2E002020: icon fid (version 3)
  w.putU32(0x2E002020'u32)
  w.putI32(3)
  w.putStr("")                      # IconFid
  w.putU8(0)                        # boolbyte
  # trailing skippable chunks
  w.putSkippable(0x2E002025'u32, newSeq[byte](8))
  w.putSkippable(0x2E002026'u32, newSeq[byte](8))
  w.putSkippable(0x2E002027'u32, newSeq[byte](8))
  w.putU32(FACADE)                  # end CGameItemModel (root) node
  result = w.buf

# --- Header user data ---------------------------------------------------------
# Four header chunks: SHeaderDesc (0x2E001003), lightmap-compute-time (0x2E001006,
# constant 0), EItemType (0x2E002000 = 1), file version (0x2E002001 = 0). Only the
# SHeaderDesc varies (collection/author/name). It mirrors the body's collector
# metadata but with its OWN Id table (so author is re-emitted fresh).
proc buildHeaderDesc(name, author, collection: string): seq[byte] =
  var w = initGbxWriter()
  w.putI32(3)                       # Id version (first Id in the header)
  w.putIdEmpty()                    # ident.id
  w.putIdLiteral(collectionId(collection))   # ident.collection
  w.putIdString(author)             # ident.author
  w.putI32(8)                       # version
  w.putStr("Items")                 # PageName
  w.putIdEmpty()                    # ParentCollectorId
  w.putI32(8)                       # Flags
  w.putU16(1)                       # CatalogPosition (short)
  w.putStr(name)                    # Name
  w.putU8(3)                        # ProdState
  result = w.buf

proc buildItemUserData(name, author, collection: string): seq[byte] =
  let desc = buildHeaderDesc(name, author, collection)
  var w = initGbxWriter()
  w.putI32(4)                       # header chunk count
  w.putU32(0x2E001003'u32); w.putU32(uint32(desc.len))
  w.putU32(0x2E001006'u32); w.putU32(8)
  w.putU32(0x2E002000'u32); w.putU32(4)
  w.putU32(0x2E002001'u32); w.putU32(4)
  w.putBytes(desc)                  # SHeaderDesc payload
  for _ in 0 ..< 8: w.putU8(0)       # lightmap compute time (filetime, 0)
  w.putI32(1)                       # EItemType = 1
  w.putI32(0)                       # file version = 0
  result = w.buf

proc itemInfo*(numNodes: int, userData: seq[byte]): GbxInfo =
  GbxInfo(
    version: 6,
    format: 'B',
    refTableCompression: gcUncompressed,
    bodyCompression: gcCompressed,
    unknownByte: 'R',
    classId: 0x2E002000'u32,
    userDataLen: userData.len,
    userData: userData,
    numNodes: numNodes,
    numExternalNodes: 0)

proc itemNodeCount*(mesh: FbxMesh): int =
  ## item + entity + staticObject + mesh subtree (1+3N) + placement param.
  5 + 3 * triGroups(mesh).len

proc buildItemGbx*(mesh: FbxMesh, materials: seq[MeshMaterial],
                   name, author, collection: string,
                   fileWriteTime: int64, sourceTag: string): seq[byte] =
  ## Full .Item.Gbx file bytes (header + framing + LZO-compressed body).
  let userData = buildItemUserData(name, author, collection)
  writeGbx(itemInfo(itemNodeCount(mesh), userData),
           buildItemBody(mesh, materials, name, author, collection, fileWriteTime, sourceTag))

proc saveItemGbx*(path: string, mesh: FbxMesh, materials: seq[MeshMaterial],
                  name, author, collection: string,
                  fileWriteTime: int64, sourceTag: string) =
  saveGbx(path, itemInfo(itemNodeCount(mesh), buildItemUserData(name, author, collection)),
          buildItemBody(mesh, materials, name, author, collection, fileWriteTime, sourceTag))
