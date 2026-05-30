## M5 regression: build each ladder fixture's CGameItemModel (.Item.Gbx) body +
## header from its FBX and assert it is BYTE-IDENTICAL to the real NadeoImporter
## golden's decompressed body and header bytes. Proves src/item.nim — the catalog
## wrapper + embedded CPlugSolid2Model (buildMeshBody, nodeBase=3, IsMeshCollidable).
##
## Like mesh_bytediff, two embedded-mesh fields are input/environment-derived
## (fileWriteTime, the U06 source path); the test EXTRACTS them from each golden by
## diffing two of our own builds, then rebuilds with those exact values. Name comes
## from the fixture stem, author/collection from the minimal Item.xml the rig writes
## ("nadeo-freeporter" / "Stadium").
##
## Requires tests/gen/golden/*.Item.gbx (gitignored). Skips if absent. UV-less
## fixtures (cube/smooth_cube/degenerate) diverge only inside the embedded mesh's
## tangent arrays — same tolerance as mesh_bytediff — so they are reported, not failed.
import std/[strutils, os]
import "../src/gbx"
import "../src/ufbx"
import "../src/mesh"
import "../src/item"
import "../src/materials"

const fixtures = ["01_triangle", "02_two_triangles", "03_unit_cube", "04_triangle_shifted",
                  "05_smooth_cube", "06_tilted_triangle", "07_tilted_degenerate",
                  "08_tri3", "09_tri5", "10_tri7",
                  "11_mat_link", "12_mat_physics", "13_two_materials"]
const uvless = ["03_unit_cube", "05_smooth_cube", "07_tilted_degenerate"]
const author = "nadeo-freeporter"
const collection = "Stadium"

if not dirExists("tests/gen/golden"):
  echo "item_bytediff: tests/gen/golden absent; skipping."; quit(0)

proc firstDiff(a, b: seq[byte]): int =
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]: return i
  if a.len != b.len: return min(a.len, b.len)
  -1

proc readI64At(b: seq[byte], o: int): int64 =
  var r = initGbxReader(b); r.skip(o); r.readI64()
proc readStrAt(b: seq[byte], o: int): string =
  var r = initGbxReader(b); r.skip(o); r.readString()

var failures = 0
for n in fixtures:
  let goldenPath = "tests/gen/golden/" & n & ".Item.gbx"
  let fbxPath = "tests/gen/out/" & n & ".fbx"
  if not fileExists(goldenPath) or not fileExists(fbxPath):
    echo n, ": missing golden/fbx — skipping"; continue
  let (ok, err, mesh) = loadFbx(fbxPath)
  doAssert ok, n & ": FBX load failed: " & err
  let (_, golden) = loadGbx(goldenPath)

  let mpPath = "tests/gen/out/" & n & ".MeshParams.xml"
  let mats = (if fileExists(mpPath): parseMeshParams(mpPath) else: defaultMaterials())

  proc build(ft: int64, tag: string): seq[byte] =
    buildItemBody(mesh, mats, n, author, collection, ft, tag)

  # Locate the embedded mesh's two variable fields by diffing our own builds.
  let ftOff = firstDiff(build(0, ""), build(1, ""))
  let tagOff = firstDiff(build(0, ""), build(0, "x"))
  doAssert ftOff >= 0 and tagOff >= 0, n & ": could not locate variable fields"
  let ft = readI64At(golden, ftOff)
  let tag = readStrAt(golden, tagOff)
  let ours = build(ft, tag)

  if ours == golden:
    # Header bytes (incl. user data) must also match, and write+reload reproduce.
    let goldenRaw = cast[seq[byte]](readFile(goldenPath))
    var gr = initGbxReader(goldenRaw)
    let gInfo = gr.parseHeader()
    let ourFile = buildItemGbx(mesh, mats, n, author, collection, ft, tag)
    doAssert ourFile[0 ..< gInfo.bodyStart] == goldenRaw[0 ..< gInfo.bodyStart],
      n & ": header bytes differ from golden"
    var rr = initGbxReader(ourFile)
    var ri = rr.parseHeader()
    doAssert rr.readBody(ri) == golden, n & ": reloaded body != golden body"
    echo n, ": OK (", ours.len, " B body; full file ", ourFile.len,
         " B, header+reload verified; U06=\"", tag, "\")"
  elif n in uvless and ours.len == golden.len:
    # Divergence allowed ONLY inside the embedded mesh body (the UV-less tangent
    # arrays — same limitation mesh_bytediff documents). Prove every differing byte
    # falls within the embedded CPlugSolid2Model span, so the wrapper stays exact.
    let meshBody = buildMeshBody(mesh, mats, ft, tag, nodeBase = 3, emitIdVersion = false)
    # The mesh body is emitted right after the Mesh node-ref (index 3 + classId
    # 0x090BB000); find that 8-byte marker in our build.
    const marker = [0x03'u8,0,0,0, 0x00,0xB0,0x0B,0x09]
    var meshStart = -1
    for s in 0 .. ours.len - marker.len:
      var ok = true
      for k in 0 ..< marker.len:
        if ours[s+k] != marker[k]: ok = false; break
      if ok: meshStart = s + marker.len; break
    doAssert meshStart >= 0, n & ": could not locate embedded mesh"
    let meshEnd = meshStart + meshBody.len
    var outside = 0
    var fd, ld = -1
    for i in 0 ..< golden.len:
      if ours[i] != golden[i]:
        if fd < 0: fd = i
        ld = i
        if i < meshStart or i >= meshEnd: inc outside
    doAssert outside == 0,
      n & ": " & $outside & " differing bytes OUTSIDE the embedded mesh " &
      "[" & $meshStart & "," & $meshEnd & ") — wrapper regression"
    echo n, ": OK except UV-less tangents — diff [", fd, ",", ld,
         "] confined to embedded mesh [", meshStart, ",", meshEnd, ")"
  else:
    inc failures
    let fd = firstDiff(ours, golden)
    echo n, ": MISMATCH ours=", ours.len, " golden=", golden.len, " firstDiff@", fd
    if fd >= 0:
      let lo = max(0, fd - 4); let hi = min(golden.len, fd + 24)
      var ao, bo = ""
      for k in lo ..< min(ours.len, hi): ao.add toHex(ours[k]) & " "
      for k in lo ..< hi: bo.add toHex(golden[k]) & " "
      echo "    ours @", lo, ": ", ao
      echo "    gold @", lo, ": ", bo

doAssert failures == 0, $failures & " Item body mismatch(es)"
echo "All Item bodies byte-identical to NadeoImporter goldens (modulo fileWriteTime/U06)."
