#!/usr/bin/env bash
# Fetches third-party deps into vendor/. Run once before building.
#
# Only gbx-net is vendored — and purely as a *reference* for the GBX chunk
# formats (it's C#, not linked into the Nim build). nadeo-freeporter is a
# self-contained CLI; it has no runtime dependency on anything here.
set -euo pipefail

VENDOR="$(cd "$(dirname "$0")" && pwd)/vendor"
mkdir -p "$VENDOR"

echo "==> gbx-net (GBX format reference)"
if [ -d "$VENDOR/gbx-net" ] && [ -n "$(ls -A "$VENDOR/gbx-net" 2>/dev/null)" ]; then
    echo "  already present: gbx-net"
else
    echo "  cloning gbx-net..."
    git clone --depth=1 "https://github.com/BigBang1112/gbx-net.git" "$VENDOR/gbx-net"
    echo "  done."
fi

echo "==> ufbx (FBX parser — single-file MIT C lib, linked into the Nim build)"
UFBX_VER="v0.22.0"
UFBX_RAW="https://raw.githubusercontent.com/ufbx/ufbx/${UFBX_VER}"
if [ -f "$VENDOR/ufbx/ufbx.c" ] && [ -f "$VENDOR/ufbx/ufbx.h" ]; then
    echo "  already present: ufbx ${UFBX_VER}"
else
    mkdir -p "$VENDOR/ufbx"
    echo "  downloading ufbx ${UFBX_VER}..."
    curl -fsSL "$UFBX_RAW/ufbx.c" -o "$VENDOR/ufbx/ufbx.c"
    curl -fsSL "$UFBX_RAW/ufbx.h" -o "$VENDOR/ufbx/ufbx.h"
    curl -fsSL "$UFBX_RAW/LICENSE" -o "$VENDOR/ufbx/LICENSE" || true
    echo "  done."
fi

echo "==> NadeoImporterMaterialLib.txt (Nadeo material catalog)"
# The material lib is a runtime data dependency: it maps material names ->
# SurfaceId / GameplayId / UV layers. It ships inside Nadeo's official
# NadeoImporter CDN zip (same zip forzamania's "Download NadeoImporter"
# button grabs). We fetch the zip and extract ONLY the .txt — we don't
# redistribute Nadeo's files in the repo (vendor/ is gitignored).
NADEO_VER="2022_07_12"
NADEO_URL="https://nadeo-download.cdn.ubi.com/trackmania/NadeoImporter_${NADEO_VER}.zip"
MATLIB="$VENDOR/nadeo/NadeoImporterMaterialLib.txt"
if [ -f "$MATLIB" ]; then
    echo "  already present: NadeoImporterMaterialLib.txt"
else
    mkdir -p "$VENDOR/nadeo"
    tmp="$(mktemp -d)"
    echo "  downloading NadeoImporter_${NADEO_VER}.zip..."
    curl -fsSL "$NADEO_URL" -o "$tmp/nadeo.zip"
    head -c2 "$tmp/nadeo.zip" | grep -q "PK" || { echo "  error: not a zip (bad URL / error page)" >&2; rm -rf "$tmp"; exit 1; }
    # -j junks internal paths, -o overwrites; match the file wherever it sits in the zip.
    unzip -o -j "$tmp/nadeo.zip" '*NadeoImporterMaterialLib.txt' -d "$VENDOR/nadeo" >/dev/null
    rm -rf "$tmp"
    [ -f "$MATLIB" ] && echo "  done." || { echo "  error: txt not found in zip" >&2; exit 1; }
fi

echo ""
echo "All deps ready."
