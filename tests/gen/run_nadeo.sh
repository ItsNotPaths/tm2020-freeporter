#!/usr/bin/env bash
# Drive the real NadeoImporter (Windows) under Proton's bundled wine to produce
# golden .Mesh.Gbx/.Shape.Gbx for our synthetic fixtures. Mirrors the recipe in
# tests/README.md. Run from the repo root:  bash tests/gen/run_nadeo.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$HOME/.steam/debian-installation"
PROTON="$S/steamapps/common/Proton 11.0"
PFX="$S/steamapps/compatdata/3529941548/pfx"
EXE="/run/media/paths/SSS-Core/python projects/forzamania-release/tools/NadeoImporter.exe"
USERDIR="$PFX/drive_c/users/steamuser/Documents/Trackmania"
SUB="freeporter-probe"                # relative path under Work/Items/ and Items/
WORK="$USERDIR/Work/Items/$SUB"
# Importer writes compiled gbx to Items/<SUB>/ (mirrors the Work/Items/<SUB>/
# source path: the leading "/Items/" in the arg maps to the Items/ root).
OUT="$USERDIR/Items/$SUB"
DEST="$REPO/tests/gen/golden"

export WINEPREFIX="$PFX"
export LD_LIBRARY_PATH="$PROTON/files/lib64:$PROTON/files/lib:${LD_LIBRARY_PATH:-}"
export WINEDLLPATH="$PROTON/files/lib64/wine:$PROTON/files/lib/wine"
export PATH="$PROTON/files/bin:$PATH"
export WINEDEBUG="-all"

mkdir -p "$WORK" "$DEST"

# MeshParams.xml for a fixture whose single material is "Mat0":
# Static mesh, Stadium collection, Mat0 -> stock PlatformTech / Asphalt physics.
write_meshparams() {
  local stem="$1"
  cat > "$WORK/${stem}.MeshParams.xml" <<XML
<?xml version="1.0" ?>
<MeshParams Scale="1.0" MeshType="Static" Collection="Stadium" FbxFile="${stem}.fbx">
    <Materials>
        <Material Name="Mat0" Link="PlatformTech" PhysicsId="Asphalt" />
    </Materials>
    <Lights/>
</MeshParams>
XML
}

for fbx in "$REPO"/tests/gen/out/*.fbx; do
  stem="$(basename "$fbx" .fbx)"
  echo "===== $stem ====="
  cp "$fbx" "$WORK/$stem.fbx"
  write_meshparams "$stem"
  # Importer resolves the path arg relative to Work/, leading slash.
  wine "$EXE" Mesh "/Items/$SUB/$stem.fbx"
  echo "  importer exit: $?"
done

echo "===== importer output dir ($OUT) ====="
ls -la "$OUT" 2>&1 || echo "  (no output dir)"

# Copy compiled gbx back with canonical casing.
shopt -s nullglob
for g in "$OUT"/*.Mesh.Gbx "$OUT"/*.Shape.Gbx "$OUT"/*.gbx; do
  cp -v "$g" "$DEST/"
done
echo "===== DEST ($DEST) ====="
ls -la "$DEST"
