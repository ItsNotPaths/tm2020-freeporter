#!/usr/bin/env bash
# Determinism check (differential-RE guardrail): run the real NadeoImporter on the
# SAME fbx twice and capture each .Mesh.Gbx separately, so we can diff them. Any
# byte that differs between two identical runs is non-deterministic (lightmap atlas
# packing / build order) — see memory differential-re-method. Mirrors run_nadeo.sh.
# Usage:  bash tests/gen/determinism_check.sh [fixture-stem]   (default 03_unit_cube)
set -uo pipefail

STEM="${1:-03_unit_cube}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$HOME/.steam/debian-installation"
PROTON="$S/steamapps/common/Proton 11.0"
PFX="$S/steamapps/compatdata/3529941548/pfx"
EXE="/run/media/paths/SSS-Core/python projects/forzamania-release/tools/NadeoImporter.exe"
USERDIR="$PFX/drive_c/users/steamuser/Documents/Trackmania"
SUB="freeporter-determinism"
WORK="$USERDIR/Work/Items/$SUB"
OUT="$USERDIR/Items/$SUB"
DEST="/tmp/nfp_determinism"

export WINEPREFIX="$PFX"
export LD_LIBRARY_PATH="$PROTON/files/lib64:$PROTON/files/lib:${LD_LIBRARY_PATH:-}"
export WINEDLLPATH="$PROTON/files/lib64/wine:$PROTON/files/lib/wine"
export PATH="$PROTON/files/bin:$PATH"
export WINEDEBUG="-all"

rm -rf "$DEST"; mkdir -p "$WORK" "$DEST"
cp "$REPO/tests/gen/out/$STEM.fbx" "$WORK/$STEM.fbx"
cat > "$WORK/$STEM.MeshParams.xml" <<XML
<?xml version="1.0" ?>
<MeshParams Scale="1.0" MeshType="Static" Collection="Stadium" FbxFile="$STEM.fbx">
    <Materials>
        <Material Name="Mat0" Link="PlatformTech" PhysicsId="Asphalt" />
    </Materials>
    <Lights/>
</MeshParams>
XML

for run in A B; do
  echo "===== run $run ====="
  rm -f "$OUT/$STEM.Mesh.gbx"
  wine "$EXE" Mesh "/Items/$SUB/$STEM.fbx"
  echo "  importer exit: $?"
  if [ -f "$OUT/$STEM.Mesh.gbx" ]; then
    cp "$OUT/$STEM.Mesh.gbx" "$DEST/${STEM}.run${run}.Mesh.gbx"
    echo "  captured -> $DEST/${STEM}.run${run}.Mesh.gbx"
  else
    echo "  !! no output produced"; ls -la "$OUT" 2>&1 | head
  fi
done

echo "===== raw compare ====="
A="$DEST/${STEM}.runA.Mesh.gbx"; B="$DEST/${STEM}.runB.Mesh.gbx"
if [ -f "$A" ] && [ -f "$B" ]; then
  if cmp -s "$A" "$B"; then
    echo "RAW FILES IDENTICAL ($(wc -c <"$A") bytes) — deterministic at the file level."
  else
    echo "RAW FILES DIFFER:"; cmp "$A" "$B" | head
    echo "(decompress + locate with: nim c -r tests/mesh_diff.nim $STEM)"
  fi
fi
