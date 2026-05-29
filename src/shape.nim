## .Shape.Gbx (CPlugSurface, class 0x0900C000) body generation.
##
## The collision surface is a CPlugSurface holding a single Mesh surf (surfId 7):
## the raw mesh vertices + a triangle list, with no transform applied (collision
## coords are the FBX control points verbatim — established by differential RE,
## see tests/probe_shape.nim and todo.md).
##
## Body layout (chunk 0x0900C003, fully decoded & confirmed byte-identical against
## the real NadeoImporter on the 4-fixture ladder):
##   u32   chunkId            0x0900C003
##   i32   chunk version      4
##   i32   surfVersion        2
##   i32   surfId             7        (Mesh)
##   i32   mesh version       7
##   i32   nVerts ; Vec3[nVerts]       (raw float32 positions, untransformed)
##   i32   nTris  ; Triangle[nTris]    (Int3 indices, u8, u8, i16 surfaceIndex)
##   Vec3  GameplayMainDir    (0,0,1)
##   i32   nMaterials         0
##   <126-byte constant tail> U02 ushort[]=[0], skel noderef -> CPlugSkel v19
##                            (1 identity joint), two 0xFACADE01 terminators.
##
## The tail is geometry-independent (proven identical across triangle/cube/etc.)
## so it is emitted verbatim; it carries the single surface-id (0 = Concrete) and
## an embedded identity skeleton that NadeoImporter always writes. When real
## materials / PhysicsId come online (M4), the per-triangle surfaceIndex and the
## tail's U02 array become variable — differential RE of a PhysicsId mutation maps
## those (todo.md "NEXT SLICE").

import gbx
import ufbx

const shapeTail = [
  0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0xA0'u8,
  0x0B'u8, 0x09'u8, 0x00'u8, 0xA0'u8, 0x0B'u8, 0x09'u8, 0x13'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x03'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0x01'u8, 0x00'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8, 0xFF'u8,
  0xFF'u8, 0xFF'u8, 0x00'u8, 0x00'u8, 0x80'u8, 0x3F'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x80'u8, 0x3F'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x80'u8, 0x3F'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8, 0xDE'u8,
  0xCA'u8, 0xFA'u8, 0x01'u8, 0xDE'u8, 0xCA'u8, 0xFA'u8,
]

proc putF32(w: var GbxWriter, v: float32) = w.putU32(cast[uint32](v))

proc buildShapeBody*(mesh: FbxMesh): seq[byte] =
  ## Serialize the decompressed CPlugSurface body for `mesh`. Triangulates each
  ## face into a fan; every face in our fixtures is already a triangle.
  var w = initGbxWriter()
  w.putU32(0x0900C003'u32)   # chunk id
  w.putI32(4)                # chunk version
  w.putI32(2)                # surfVersion
  w.putI32(7)                # surfId = Mesh
  w.putI32(7)                # mesh version

  # NadeoImporter does NOT emit collision vertices in raw control-point order:
  # it assigns each a new index on FIRST ENCOUNTER while walking face corners
  # (confirmed by differential RE on the cube — face (4,6,5) makes 6 precede 5).
  # Build that remap (FBX position index -> collision index) plus the ordered
  # vertex list, then emit triangles using the remapped indices.
  var remap = newSeq[int](mesh.positions.len div 3)
  for i in 0 ..< remap.len: remap[i] = -1
  var order: seq[int] = @[]   # FBX position indices, first-encounter order

  proc collIdx(corner: int): int32 =
    let pi = mesh.cornerPos[corner]
    if remap[pi] < 0:
      remap[pi] = order.len
      order.add pi
    int32(remap[pi])

  var tris: seq[array[3, int32]] = @[]
  for f in mesh.faces:
    for k in 1 ..< f.count - 1:
      tris.add [collIdx(f.first), collIdx(f.first + k), collIdx(f.first + k + 1)]

  w.putI32(int32(order.len))
  for pi in order:
    w.putF32(mesh.positions[pi*3 + 0])
    w.putF32(mesh.positions[pi*3 + 1])
    w.putF32(mesh.positions[pi*3 + 2])

  w.putI32(int32(tris.len))
  for t in tris:
    w.putI32(t[0]); w.putI32(t[1]); w.putI32(t[2])
    w.putU8(0)               # U02
    w.putU8(0)               # U03
    w.putU16(0)              # surfaceIndex

  # GameplayMainDir (0,0,1)
  w.putF32(0.0'f32); w.putF32(0.0'f32); w.putF32(1.0'f32)
  w.putI32(0)                # nMaterials

  w.putBytes(shapeTail)
  result = w.buf

proc shapeInfo*(): GbxInfo =
  ## Header/framing constants for a .Shape.Gbx, matching the NadeoImporter
  ## goldens exactly: GBX v6, binary, uncompressed ref table, LZO-compressed body,
  ## CPlugSurface class, NO header user data, and 2 nodes (the surface + its
  ## embedded CPlugSkel). numExternalNodes 0 (no external ref table).
  GbxInfo(
    version: 6,
    format: 'B',
    refTableCompression: gcUncompressed,
    bodyCompression: gcCompressed,
    unknownByte: 'R',
    classId: 0x0900C000'u32,
    userDataLen: 0,
    userData: @[],
    numNodes: 2,
    numExternalNodes: 0)

proc buildShapeGbx*(mesh: FbxMesh): seq[byte] =
  ## Full .Shape.Gbx file bytes (header + framing + LZO-compressed body). The
  ## compressed bytes differ from Nadeo's (LZO1X-1 vs -999) but decompress to the
  ## byte-identical body; the game reads the decompressed content.
  writeGbx(shapeInfo(), buildShapeBody(mesh))

proc saveShapeGbx*(path: string, mesh: FbxMesh) =
  saveGbx(path, shapeInfo(), buildShapeBody(mesh))
