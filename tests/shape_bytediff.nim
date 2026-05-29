## M3 regression: build each ladder fixture's CPlugSurface (Shape) body from its
## FBX and assert it is BYTE-IDENTICAL to the real NadeoImporter golden's
## decompressed body. Proves the Shape body generator (src/shape.nim) — geometry
## front + first-encounter vertex ordering + constant skel/material tail.
##
## Requires the generated goldens in tests/gen/golden/ (gitignored; produced by
## tests/gen/run_nadeo.sh). Skips with a notice if they are absent.
import std/[strutils, os]
import "../src/gbx"
import "../src/ufbx"
import "../src/shape"

const fixtures = ["01_triangle", "02_two_triangles", "03_unit_cube", "04_triangle_shifted"]

if not dirExists("tests/gen/golden"):
  echo "shape_bytediff: tests/gen/golden absent — run tests/gen/run_nadeo.sh; skipping."
  quit(0)

var failures = 0
for n in fixtures:
  let goldenPath = "tests/gen/golden/" & n & ".Shape.gbx"
  let fbxPath = "tests/gen/out/" & n & ".fbx"
  if not fileExists(goldenPath) or not fileExists(fbxPath):
    echo n, ": missing golden/fbx — skipping"
    continue
  let (ok, err, mesh) = loadFbx(fbxPath)
  doAssert ok, n & ": FBX load failed: " & err
  let ours = buildShapeBody(mesh)
  let (_, golden) = loadGbx(goldenPath)

  # Full-file checks: (1) header/framing byte-identical to the golden's pre-body
  # region; (2) writing then re-reading our file reproduces the body exactly.
  let goldenRaw = cast[seq[byte]](readFile(goldenPath))
  var gr = initGbxReader(goldenRaw)
  let gInfo = gr.parseHeader()
  let ourFile = buildShapeGbx(mesh)
  doAssert ourFile[0 ..< gInfo.bodyStart] == goldenRaw[0 ..< gInfo.bodyStart],
    n & ": header bytes differ from golden"
  var rr = initGbxReader(ourFile)
  var ri = rr.parseHeader()
  doAssert rr.readBody(ri) == golden, n & ": reloaded body != golden body"

  if ours == golden:
    echo n, ": OK (", ours.len, " bytes body; full file ", ourFile.len, " B, header+reload verified)"
  else:
    inc failures
    var firstDiff = -1
    for i in 0 ..< min(ours.len, golden.len):
      if ours[i] != golden[i]: firstDiff = i; break
    echo n, ": MISMATCH ours=", ours.len, " golden=", golden.len,
         " firstDiff@", firstDiff

doAssert failures == 0, $failures & " Shape body mismatch(es)"
echo "All Shape bodies byte-identical to NadeoImporter goldens."
