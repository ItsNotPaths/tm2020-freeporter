## M4 structural probe — fully decode the decompressed CPlugSolid2Model body
## (.Mesh.Gbx, class/chunk 0x090BB000 version 32) field-by-field against gbx-net,
## printing a labeled offset map. No Proton: runs on the ladder goldens we already
## have (tests/gen/golden/*.Mesh.gbx).
##
## Layout cracked 2026-05-29 (see memory mesh-body-structure):
##   CPlugSolid2Model.Chunk090BB000 v32
##     version, U01(id), ShadedGeom[] (5 i32 each at v32),
##     visuals = ArrayNodeRef_deprec<CPlugVisual> (deprecVersion i32, count, refs)
##       -> CPlugVisualIndexedTriangles (0x0901E000) node, chunk loop:
##            0x09006001 id, 0x09006005 int3[], 0x09006009 float,
##            0x0900600B Split[], 0x0900600F (Version/Flags/numTexCoordSets/Count/
##              VertexStreams ListNodeRef -> CPlugVertexStream / TexCoords / bbox /
##              BitmapElemToPack[] / UvGroups / U02,U03,U04),
##            then CPlugVisualIndexed index buffer (0x0906A00x).
##       CPlugVertexStream (0x09056000): version,count,flags,streamModel(-1),
##         DataDecl[] (Position Float3, Normal Dec3N, TexCoord0 Float2,
##         TexCoord1 Float2 = LIGHTMAP, TangentU/V Dec3N), bool, then a planar
##         array per decl (Vec3[count] / Dec3N-4B[count] / Vec2[count]).
##     materialIds (ArrayId), customMaterials count, materials (ArrayNodeRef),
##     skel (NodeRef CPlugSkel), then the long v32 tail.
##
## Run: nim c -r tests/mesh_probe.nim [fixture-stem]   (default 01_triangle)

import std/[os, strutils]
import "../src/gbx"

const FACADE = 0xFACADE01'u32

# Vertex-declaration enums (CPlugVertexStream.chunkl).
const vdclType = ["U01","Float2","Float3","Float4","Color","Int32","6","7",
                  "8","9","10","11","12","13","Dec3N"]
const vdcl = ["Position","Position1","TgtRotation","BlendWeight","BlendIndices",
              "Normal","Normal1","PointSize","Color0","Color1","TexCoord0",
              "TexCoord1","TexCoord2","TexCoord3","TexCoord4","TexCoord5",
              "TexCoord6","TexCoord7","TangentU","TangentU1","TangentV",
              "TangentV1","Color2"]

proc nm(a: openArray[string], i: int): string =
  if i >= 0 and i < a.len: a[i] else: "?" & $i

var depth = 0
proc pad(): string = repeat("  ", depth)

proc f(r: var GbxReader, name: string): float32 =
  let p = r.pos; result = r.readF32()
  echo "@", align($p,5), " ", pad(), name, " = ", $result

proc i(r: var GbxReader, name: string): int32 =
  let p = r.pos; result = r.readI32()
  echo "@", align($p,5), " ", pad(), name, " = ", $result

proc u(r: var GbxReader, name: string): uint32 =
  let p = r.pos; result = r.readU32()
  echo "@", align($p,5), " ", pad(), name, " = 0x", toHex(result)

proc bl(r: var GbxReader, name: string): bool =
  let p = r.pos; let v = r.readI32(); result = v != 0
  echo "@", align($p,5), " ", pad(), name, " = ", $result

proc ids(r: var GbxReader, name: string): string =
  let p = r.pos; result = r.readId()
  echo "@", align($p,5), " ", pad(), name, " = id\"", result, "\""

proc hexAround(body: seq[byte], pos: int, n = 64) =
  let hi = min(body.len, pos + n)
  var line = ""
  for k in pos ..< hi: line.add toHex(body[k]) & " "
  echo "    >> next ", (hi-pos), " bytes @", pos, ": ", line

# --- vertex stream -----------------------------------------------------------
proc readVertexStream(r: var GbxReader, body: seq[byte]) =
  let ver = r.i("VStream.version")
  let cnt = r.i("VStream.count")
  discard r.u("VStream.flags")
  let model = r.i("VStream.streamModel(ref)")
  if cnt == 0 or model != -1:
    echo pad(), "(no inline data)"; return
  let nDecl = r.i("nDataDecls")
  type Decl = tuple[typ, wc: int]
  var decls: seq[Decl] = @[]
  for d in 0 ..< nDecl:
    let p = r.pos
    let flags1 = r.readU32()
    let flags2 = r.readU32()
    let wc = int(flags1 and 0x1FF)
    let typ = int((flags1 shr 9) and 0x1FF)
    var extra = ""
    if (flags2 and 0xFFC'u32) != 0:
      let u02 = r.readU16(); let off = r.readU16()
      extra = " u02=" & $u02 & " offset=" & $off
    decls.add (typ, wc)
    echo "@", align($p,5), " ", pad(), "decl[", d, "] ", nm(vdclType,typ), " ",
         nm(vdcl,wc), extra, " (flags1=0x", toHex(flags1), ")"
  if ver == 0: return
  discard r.bl("VStream.bool")
  for d in decls:
    let p = r.pos
    case d.typ
    of 2:  # Float3 -> Vec3[count]
      r.skip(12 * cnt)
      echo "@", align($p,5), " ", pad(), nm(vdcl,d.wc), " Vec3[", cnt, "] (", 12*cnt, "B)"
    of 1:  # Float2 -> Vec2[count]
      let label = nm(vdcl,d.wc)
      # print the actual UV values — this is where the lightmap (TexCoord1) lives
      var vals = ""
      for k in 0 ..< cnt:
        let x = r.readF32(); let y = r.readF32()
        vals.add "(" & $x & "," & $y & ") "
      echo "@", align($p,5), " ", pad(), label, " Vec2[", cnt, "] = ", vals
    of 14: # Dec3N packed normal/tangent -> 4 bytes each
      r.skip(4 * cnt)
      echo "@", align($p,5), " ", pad(), nm(vdcl,d.wc), " Dec3N[", cnt, "] (", 4*cnt, "B)"
    else:
      echo "@", align($p,5), " ", pad(), "UNKNOWN decl type ", d.typ, " — stopping"
      hexAround(body, r.pos); quit 1

# --- generic node chunk loop -------------------------------------------------
proc readNode(r: var GbxReader, body: seq[byte], classId: uint32)

proc readNodeRef(r: var GbxReader, body: seq[byte], name: string): bool =
  let idx = r.i(name & " (nodeIndex)")
  if idx == -1: return false
  let cls = r.u(name & " classId")
  inc depth
  r.readNode(body, cls)
  dec depth
  return true

proc readNode(r: var GbxReader, body: seq[byte], classId: uint32) =
  echo pad(), "== node 0x", toHex(classId), " =="
  var guard = 0
  while true:
    inc guard
    if guard > 64 or r.remaining < 4:
      echo pad(), "(loop end / out of bytes)"; return
    let cp = r.pos
    let chunkId = r.readU32()
    if chunkId == FACADE:
      echo "@", align($cp,5), " ", pad(), "FACADE"; return
    echo "@", align($cp,5), " ", pad(), "chunk 0x", toHex(chunkId)
    inc depth
    case chunkId
    of 0x09006001'u32: discard r.ids("id")
    of 0x09006005'u32:
      let n = r.i("SubVisuals.count"); r.skip(12*n)
    of 0x09006009'u32: discard r.f("float")
    of 0x0900600B'u32:
      let n = r.i("Splits.count"); r.skip(32*n)  # int,int,box(6f)
    of 0x0900600F'u32:
      let ver = r.i("Visual.version")
      let flags = r.u("Visual.flags(raw)")
      let nTex = r.i("numTexCoordSets")
      let cnt = r.i("Visual.Count")
      let nvs = r.i("VertexStreams.count")
      for s in 0 ..< nvs:
        discard r.readNodeRef(body, "  vstream[" & $s & "]")
      if nTex != 0:
        echo pad(), "!! numTexCoordSets=", nTex, " (inline texcoords not decoded)"
        hexAround(body, r.pos); quit 1
      # SkinData if (flags&7)!=0 — not expected for static meshes
      if (flags and 7'u32) != 0:
        echo pad(), "!! SkinData present (flags&7) — not decoded"; hexAround(body, r.pos); quit 1
      # BoundingBox = 6 floats
      discard r.f("bbox.minX"); discard r.f("bbox.minY"); discard r.f("bbox.minZ")
      discard r.f("bbox.maxX"); discard r.f("bbox.maxY"); discard r.f("bbox.maxZ")
      let nb = r.i("BitmapElemToPack.count"); r.skip(20*nb)
      if ver >= 5:
        let ng = r.i("UvGroups.count"); r.skip(2*ng)
        if ver >= 6:
          discard r.i("Visual.U02")
          let u03 = r.i("Visual.U03")
          if u03 > 0: r.skip(u03 - 4)
    of 0x09006010'u32:
      discard r.i("Visual.version(010)")
      let morph = r.i("MorphCount")
      if morph > 0:
        echo pad(), "!! MorphCount>0"; hexAround(body, r.pos); quit 1
    of 0x09056000'u32: r.readVertexStream(body)
    of 0x0902C002'u32:
      let nr = r.i("Visual3D.CMwNod(ref)")
      if nr != -1: discard r.readNodeRef(body, "  v3d.node")
    of 0x0902C004'u32:
      let t1 = r.i("Tangents1.count"); r.skip(t1)   # byte-packed; 0 here
      let t2 = r.i("Tangents2.count"); r.skip(t2)
    of 0x0906A000'u32:
      let n = r.i("IndexCount"); r.skip(2*n)
      echo pad(), "indices u16[", n, "]"
    of 0x0906A001'u32:
      let has = r.bl("hasIndexBuffer")
      if has:
        inc depth
        r.readNode(body, 0x09057000'u32)   # CPlugIndexBuffer, inline (no index/classId)
        dec depth
    of 0x09057000'u32, 0x09057001'u32:   # CPlugIndexBuffer
      discard r.i("IndexBuffer.flags")
      let n = r.i("IndexBuffer.count")
      if chunkId == 0x09057000'u32:
        r.skip(2*n)                       # raw u16 indices
      else:
        var cur = 0; var s = ""           # delta-encoded i16 indices
        for k in 0 ..< n:
          cur += int(cast[int16](r.readU16())); s.add $cur & " "
        echo pad(), "indices(delta) = ", s
    of 0x0902C003'u32:
      echo pad(), "!! CPlugVisual3D inline verts chunk — stopping to inspect"
      hexAround(body, r.pos); quit 1
    else:
      echo pad(), "UNKNOWN chunk 0x", toHex(chunkId), " — stopping"
      hexAround(body, r.pos); quit 1
    dec depth

proc main() =
  let stem = if paramCount() >= 1: paramStr(1) else: "01_triangle"
  let path = "tests/gen/golden/" & stem & ".Mesh.gbx"
  if not fileExists(path):
    echo "missing ", path; quit 0
  let (info, body) = loadGbx(path)
  echo "=== ", path, " | body=", body.len, "B nodes=", info.numNodes, " ==="

  var r = initGbxReader(body)
  doAssert r.readU32() == 0x090BB000'u32
  echo "@    0 chunk 0x090BB000"
  let ver = r.i("version"); doAssert ver == 32
  discard r.ids("U01")
  let nGeom = r.i("nShadedGeoms")
  for g in 0 ..< nGeom:
    discard r.i("  shadedGeom.visualIndex")
    discard r.i("  shadedGeom.materialIndex")
    discard r.i("  shadedGeom.u01")
    discard r.i("  shadedGeom.lodMask")
    discard r.i("  shadedGeom.u02(v32)")
  discard r.i("visuals.deprecVersion")
  let nVis = r.i("visuals.count")
  for v in 0 ..< nVis:
    discard r.readNodeRef(body, "visual[" & $v & "]")
  # outer tail
  echo "--- outer tail @", r.pos, " ---"
  let nMat = r.i("materialIds.count")
  for m in 0 ..< nMat: discard r.ids("  materialId")
  let custom = r.i("customMaterials.count (v29+)")
  if custom == 0:
    let nMatRef = r.i("materials.count")
    for m in 0 ..< nMatRef: discard r.readNodeRef(body, "  material[" & $m & "]")
  discard r.readNodeRef(body, "skel")
  let nLod = r.i("lodMaxDistAtFov90.count")
  for k in 0 ..< nLod: discard r.f("  lodDist")
  discard r.i("visCstType")
  let hasPLG = r.bl("hasPreLightGen")
  if hasPLG:
    # archive PreLightGen (CPlugSolid2Model.chunkl): carries the lightmap packing
    # params — note the 0.05/0.95 floats mirror the TexCoord1 (lightmap) inset.
    inc depth
    let plgVer = r.i("PLG.version")
    discard r.i("PLG.int")
    discard r.f("PLG.float")
    discard r.bl("PLG.bool")
    for k in 0 ..< 8: discard r.f("PLG.f" & $k)
    discard r.i("PLG.spriteCount.x"); discard r.i("PLG.spriteCount.y")
    let nb = r.i("PLG.boxaligned.count")
    for k in 0 ..< nb:
      for c in 0 ..< 6: discard r.f("  box.f" & $c)
    if plgVer >= 1:
      let ng = r.i("PLG.uvGroups.count"); r.skip(16*ng)
    dec depth
  let ft = r.readI64()  # FileTime
  echo "@", align($(r.pos-8),5), " fileWriteTime (i64) = ", ft
  proc st(r: var GbxReader, name: string): string =
    let p = r.pos; result = r.readString()
    echo "@", align($p,5), " ", name, " = \"", result, "\""
  discard r.st("U03(string)")
  discard r.st("materialsFolderName")           # v7
  discard r.st("U04(string)")                   # v19
  let nLights = r.i("lights.count")             # v8
  if nLights != 0:
    echo "!! lights present — not decoded"; hexAround(body, r.pos); quit 1
  let nLUM = r.i("lightUserModels.count")       # v10
  for k in 0 ..< nLUM: discard r.readNodeRef(body, "  lightUserModel")
  let nLI = r.i("lightInsts.count")             # v10
  for k in 0 ..< nLI: (discard r.i("  LI.modelIndex"); discard r.i("  LI.socketIndex"))
  discard r.i("damageZone")                     # v11
  discard r.u("flags")                          # v12
  discard r.i("U05")                            # v13
  discard r.st("U06(string)")                   # v14
  discard r.i("U07")                            # v30
  # customMaterials Material[custom] (count read far earlier = `custom`)
  for m in 0 ..< custom:
    let nm = r.st("  customMaterial[" & $m & "].name")
    if nm.len == 0:
      echo "  !! empty material name -> CPlugMaterialUserInst (not decoded)"
      hexAround(body, r.pos); quit 1
  let nJoints = r.i("joints.count")             # v20 ArrayId
  for k in 0 ..< nJoints: discard r.ids("  joint")
  let nU10 = r.i("U10.count"); r.skip(4*nU10)   # v22
  let u11 = r.i("U11"); doAssert u11 == 0       # v23
  let nU12 = r.i("U12.count"); r.skip(4*nU12)   # v23
  discard r.i("U13")                            # v24
  discard r.readNodeRef(body, "U14")            # v25
  discard r.f("U15"); discard r.f("U16")        # v25
  discard r.ids("U17")                          # v27
  let u18 = r.i("U18"); doAssert u18 == 0       # v31
  echo "--- end of body @", r.pos, " / ", body.len, " (remaining ", r.remaining, ") ---"
  if r.remaining > 0: hexAround(body, r.pos, min(64, r.remaining))

main()
