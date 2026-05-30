## M5 structural probe — decode the .Item.Gbx (CGameItemModel 0x2E002000) body
## chunk-by-chunk against gbx-net's CGameCtnCollector + CGameItemModel chunkls,
## printing a labeled offset map. Runs on the ladder goldens (tests/gen/golden/
## *.Item.gbx); no Proton needed.
##
## The item is a catalog wrapper: CGameCtnCollector metadata chunks (page/ident/
## name/description/skin/catalog) then CGameItemModel chunks ending at the modern
## descriptor 0x2E002019, whose entityModel noderef -> CPlugStaticObjectModel
## (0x09159000), an archive embedding our already-solved Mesh + Shape bodies.
##
## Run: nim c -r tests/item_probe.nim [stem]   (default 01_triangle)

import std/[os, strutils]
import "../src/gbx"

const FACADE = 0xFACADE01'u32

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

proc ids(r: var GbxReader, name: string): string =
  let p = r.pos; result = r.readId()
  echo "@", align($p,5), " ", pad(), name, " = id\"", result, "\""

proc bb(r: var GbxReader, name: string): int =
  let p = r.pos; result = int(r.readU8())
  echo "@", align($p,5), " ", pad(), name, " = ", result

proc strv(r: var GbxReader, name: string): string =
  let p = r.pos; result = r.readString()
  echo "@", align($p,5), " ", pad(), name, " = \"", result, "\""

proc noderef(r: var GbxReader, name: string): int32 =
  ## A node-ref index (does NOT recurse; just reports the index/classId if inline).
  let p = r.pos; result = r.readI32()
  if result == -1:
    echo "@", align($p,5), " ", pad(), name, " = null"
  else:
    let cls = r.readU32()
    echo "@", align($p,5), " ", pad(), name, " = node #", result,
         " classId 0x", toHex(cls)

proc identv(r: var GbxReader, name: string) =
  let id = r.readId(); let col = r.readId(); let auth = r.readId()
  echo pad(), name, " = {id\"", id, "\" collection\"", col, "\" author\"", auth, "\"}"

proc hexAround(body: seq[byte], pos: int, n = 48) =
  let hi = min(body.len, pos + n)
  var line = ""
  for k in pos ..< hi: line.add toHex(body[k]) & " "
  echo "    >> next ", (hi-pos), " bytes @", pos, ": ", line

proc findPattern(body: seq[byte], pat: openArray[byte], start: int): int =
  ## First offset >= start where `pat` occurs, else -1.
  for s in start .. body.len - pat.len:
    var ok = true
    for k in 0 ..< pat.len:
      if body[s+k] != pat[k]: ok = false; break
    if ok: return s
  return -1

# Unique terminator of a CPlugSolid2Model body (mesh.nim): skippable chunk
# 0x090BB002 + "PIKS" + size 8 + 8 zero bytes + FACADE.
const meshEnd = [
  0x02'u8,0xB0,0x0B,0x09, 0x50,0x49,0x4B,0x53, 0x08,0,0,0, 0,0,0,0, 0,0,0,0,
  0x01'u8,0xDE,0xCA,0xFA]
# CPlugSurface (shape.nim) ends with two FACADEs after the embedded CPlugSkel.
const shapeEnd = [0x01'u8,0xDE,0xCA,0xFA, 0x01,0xDE,0xCA,0xFA]

# --- CGameCommonItemEntityModel (0x2E027000) node -----------------------------
proc iso4(r: var GbxReader, name: string) =
  ## 3x4 transform matrix (12 float32). Reports whether it is identity.
  var m: array[12, float32]
  for k in 0 ..< 12: m[k] = r.readF32()
  let ident = m == [1f,0,0, 0,1,0, 0,0,1, 0,0,0]
  echo pad(), name, " = ", (if ident: "identity" else: $m)

proc readEntityModel(r: var GbxReader, body: seq[byte]) =
  ## node #1: single chunk 0x2E027000. The static object (mesh+shape) lives in
  ## the v4+ StaticObject noderef; the embedded mesh/shape bodies are skipped by
  ## locating their unique terminators (they are our byte-exact builders' output).
  inc depth
  let cid = r.u("entity.chunkId")
  doAssert cid == 0x2E027000'u32, "expected entity chunk"
  let ver = r.i("entity.version")
  inc depth
  if ver >= 4:
    let so = r.noderef("StaticObject")    # CPlugStaticObjectModel 0x09159000
    if so != -1:
      inc depth
      # archive: int Version, CPlugSolid2Model Mesh, boolbyte IsMeshCollidable,
      #          if !IsMeshCollidable: CPlugSurface Shape.
      discard r.i("StaticObj.archiveVersion")
      let meshRef = r.noderef("Mesh")     # 0x090BB000 node
      if meshRef != -1:
        let me = findPattern(body, meshEnd, r.pos)
        doAssert me >= 0, "mesh terminator not found"
        let after = me + meshEnd.len
        echo pad(), "  [mesh body @", r.pos, "..", after, " (", after - r.pos, "B) — skipped]"
        r.skip(after - r.pos)
      let collidable = r.bb("IsMeshCollidable(boolbyte)")
      if collidable == 0:
        let shapeRef = r.noderef("Shape")  # 0x0900C000 node
        if shapeRef != -1:
          let se = findPattern(body, shapeEnd, r.pos)
          doAssert se >= 0, "shape terminator not found"
          let after = se + shapeEnd.len
          echo pad(), "  [shape body @", r.pos, "..", after, " (", after - r.pos, "B) — skipped]"
          r.skip(after - r.pos)
      dec depth
  if ver >= 2:
    discard r.noderef("TriggerShape")
    r.iso4("entity.iso4a")
    discard r.noderef("ParticleEmitter")
    let nAct = r.i("ActionModels.count")
    for k in 0 ..< nAct: discard r.noderef("  action[" & $k & "]")
    if ver <= 5: discard r.noderef("entity.CMwNod(v<=5)")
    discard r.strv("entity.s0"); discard r.strv("entity.s1")
    discard r.strv("entity.s2"); discard r.strv("entity.s3")
    discard r.strv("entity.s4")
    r.iso4("entity.iso4b")
    discard r.i("ExprValidator")
    if ver >= 5: discard r.bb("entity.byte(v5+)")
  dec depth
  # the node's chunk loop terminator
  let fc = r.u("entity.FACADE?")
  doAssert fc == FACADE, "expected entity FACADE, got 0x" & toHex(fc)
  dec depth

# --- CGameItemPlacementParam (0x2E020000) node -------------------------------
const SKIP = 0x534B4950'u32   # skippable-chunk marker ("PIKS" on disk)

proc readPlacementParam(r: var GbxReader, body: seq[byte]) =
  ## node #7: a chain of skippable chunks (placement/grid params) then FACADE.
  inc depth
  var guard = 0
  while true:
    inc guard
    if guard > 16 or r.remaining < 4:
      echo pad(), "(placement loop end @", r.pos, ")"; dec depth; return
    let cp = r.pos
    let chunkId = r.readU32()
    if chunkId == FACADE:
      echo "@", align($cp,5), " ", pad(), "FACADE (placement end)"; dec depth; return
    let marker = r.readU32()
    doAssert marker == SKIP, "placement chunk 0x" & toHex(chunkId) &
      " not skippable (marker 0x" & toHex(marker) & ")"
    let sz = int(r.readI32())
    echo "@", align($cp,5), " ", pad(), "skippable chunk 0x", toHex(chunkId),
         " (", sz, "B)"
    r.skip(sz)

# --- CGameCtnCollector / CGameItemModel body chunk loop ----------------------
proc readItemChunks(r: var GbxReader, body: seq[byte]) =
  var guard = 0
  while true:
    inc guard
    if guard > 80 or r.remaining < 4:
      echo pad(), "(loop end / out of bytes @", r.pos, ")"; return
    let cp = r.pos
    let chunkId = r.readU32()
    if chunkId == FACADE:
      echo "@", align($cp,5), " FACADE (node end)"; return
    echo "@", align($cp,5), " chunk 0x", toHex(chunkId)
    inc depth
    case chunkId
    of 0x2E001009'u32:   # CGameCtnCollector: pageName, iconFid?, parentCollectorId
      discard r.strv("pageName")
      let hasIcon = r.i("hasIconFid(bool)")
      if hasIcon != 0: discard r.noderef("iconFid")
      discard r.ids("parentCollectorId")
    of 0x2E00100B'u32:   # ident
      r.identv("Ident")
    of 0x2E00100C'u32:   # collector Name
      discard r.strv("Name")
    of 0x2E00100D'u32:   # Description
      discard r.strv("Description")
    of 0x2E001010'u32:   # default skin
      let ver = r.i("v(010)")
      discard r.noderef("DefaultSkin")
      let dir = r.strv("SkinDirectory")
      if ver >= 2 and dir.len == 0: discard r.noderef("CMwNod")
    of 0x2E001011'u32:   # internal/advanced/catalogPos/prodState
      let ver = r.i("v(011)")
      discard r.i("IsInternal")
      discard r.i("IsAdvanced")
      discard r.i("CatalogPosition")
      if ver >= 1: discard r.bb("ProdState")
    of 0x2E001012'u32:   # TM2020 4 ints
      discard r.i("c012.int0"); discard r.i("c012.int1")
      discard r.i("c012.int2"); discard r.i("c012.int3")
    of 0x2E002008'u32:   # NadeoSkinFids CMwNod?[]
      let n = r.i("NadeoSkinFids.count")
      for k in 0 ..< n: discard r.noderef("  skinFid[" & $k & "]")
    of 0x2E002009'u32:   # Cameras CMwNod[]_deprec
      discard r.i("Cameras.deprecVersion")
      let n = r.i("Cameras.count")
      for k in 0 ..< n: discard r.noderef("  cam[" & $k & "]")
    of 0x2E00200C'u32:   # race interface fid
      discard r.noderef("RaceInterfaceFid")
    of 0x2E002012'u32:   # ground point + orbital floats
      discard r.f("GroundPoint.x"); discard r.f("GroundPoint.y"); discard r.f("GroundPoint.z")
      discard r.f("PainterGroundMargin")
      discard r.f("OrbitalCenterHeightFromGround")
      discard r.f("OrbitalRadiusBase")
      discard r.f("OrbitalPreviewAngle")
    of 0x2E002015'u32:   # ItemTypeE
      discard r.i("ItemTypeE")
    of 0x2E002019'u32:   # modern model descriptor
      let ver = r.i("c019.Version")
      # itemType=1 (Ornament) -> itemTypeVersion 9; ver(15) >= 9 so no custom pre-block.
      discard r.ids("defaultWeaponName")
      discard r.noderef("phyModelCustom")     # v>=4
      discard r.noderef("visModelCustom")     # v>=5
      let nAct = r.i("actions.count")          # v>=6 ArrayNodeRef
      for k in 0 ..< nAct: discard r.noderef("  action[" & $k & "]")
      discard r.i("defaultCam(enum)")          # v>=7
      let eme = r.noderef("entityModelEdition") # v>=8
      if eme == -1:
        echo pad(), ">> entityModel follows (entityModelEdition null):"
        inc depth
        let em = r.noderef("entityModel")   # node CGameCommonItemEntityModel 0x2E027000
        if em != -1: r.readEntityModel(body)
        dec depth
      if ver >= 13:
        discard r.noderef("vfx")
        if ver >= 15: discard r.noderef("materialModifier")
    of 0x2E00201A'u32, 0x2E00201B'u32:
      discard r.noderef("CMwNod(c01A/01B)")
    of 0x2E00201D'u32:   # short
      discard r.i("c01D.short(i32?)")
    of 0x2E00201C'u32:   # default placement
      let ver = r.i("c01C.version")
      if ver >= 5:
        let dp = r.noderef("DefaultPlacement")  # CGameItemPlacementParam 0x2E020000
        if dp != -1: r.readPlacementParam(body)
      else: echo pad(), "!! c01C v<5 not decoded"; hexAround(body, r.pos); quit 1
    of 0x2E00201E'u32:   # archetype
      let ver = r.i("c01E.version")
      if ver >= 2:
        let a = r.strv("ArchetypeRef")
        if ver >= 5 and a.len == 0: discard r.noderef("ArchetypeFid")
        if ver >= 6:
          discard r.strv("SkinDirNameCustom")
          if ver >= 7: discard r.i("c01E.int(-1)")
    of 0x2E00201F'u32:   # waypoint / lightmap
      let ver = r.i("c01F.version")
      discard r.i("WaypointType")
      if ver <= 7: echo pad(), "!! c01F v<=7 (iso4) not decoded"; hexAround(body, r.pos); quit 1
      if ver >= 6:
        discard r.i("DisableLightmap(bool)")
        if ver >= 9:
          if ver <= 12: discard r.noderef("c01F.CMwNod")
          if ver >= 11:
            discard r.bb("c01F.byte")
            if ver >= 12:
              discard r.i("c01F.int_a"); discard r.i("c01F.int_b")
    of 0x2E002020'u32:   # icon fid
      let ver = r.i("c020.version")
      discard r.strv("IconFid")
      if ver >= 3: discard r.bb("c020.boolbyte")
    of 0x2E002025'u32, 0x2E002024'u32, 0x2E002026'u32, 0x2E002027'u32:
      # skippable chunks: u32 SKIP marker, u32 size, then size bytes
      let marker = r.u("  skip.marker")
      let sz = r.i("  skip.size")
      r.skip(int(sz))
      echo pad(), "  (skipped ", sz, "B; marker 0x", toHex(marker), ")"
    else:
      echo pad(), "UNKNOWN chunk 0x", toHex(chunkId), " — stopping"
      hexAround(body, r.pos); quit 1
    dec depth

proc main() =
  let stem = if paramCount() >= 1: paramStr(1) else: "01_triangle"
  let path = "tests/gen/golden/" & stem & ".Item.gbx"
  if not fileExists(path):
    echo "missing ", path; quit 0
  let (info, body) = loadGbx(path)
  echo "=== ", path, " | body=", body.len, "B nodes=", info.numNodes,
       " userDataLen=", info.userDataLen, " ==="
  var r = initGbxReader(body)
  echo "== CGameItemModel body =="
  readItemChunks(r, body)
  echo "--- stopped @", r.pos, " / ", body.len, " ---"

main()
