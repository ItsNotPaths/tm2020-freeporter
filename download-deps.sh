#!/usr/bin/env bash
# Fetches third-party deps into vendor/. Run once before building.
#
# Only gbx-net is vendored — and purely as a *reference* for the GBX chunk
# formats (it's C#, not linked into the Nim build). nadeo-freeporter is a
# self-contained CLI; it has no runtime dependency on anything here.
set -euo pipefail

VENDOR="$(cd "$(dirname "$0")" && pwd)/vendor"
mkdir -p "$VENDOR"

# Set DEPS_BUILD_ONLY=1 (CI does) to fetch only what the Nim build links/embeds
# (ufbx, minilzo, the material lib) and skip the gbx-net reference clone, which is
# C# documentation only — never compiled into the binary.
echo "==> gbx-net (GBX format reference)"
if [ "${DEPS_BUILD_ONLY:-0}" = "1" ]; then
    echo "  skipped (DEPS_BUILD_ONLY=1): reference-only, not needed to build"
elif [ -d "$VENDOR/gbx-net" ] && [ -n "$(ls -A "$VENDOR/gbx-net" 2>/dev/null)" ]; then
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

echo "==> minilzo (LZO1X codec — Oberhumer C lib, linked into the Nim build)"
# GBX bodies are LZO1X-compressed. We vendor Oberhumer's minilzo (the same
# upstream gbx-net's C# MiniLZO was ported from) and bind it via src/lzo_bridge.c.
# minilzo is 4 self-contained files: minilzo.c/.h, lzoconf.h, lzodefs.h.
MINILZO_TARBALL="https://www.oberhumer.com/opensource/lzo/download/minilzo-2.10.tar.gz"
if [ -f "$VENDOR/minilzo/minilzo.c" ]; then
    echo "  already present: minilzo"
else
    mkdir -p "$VENDOR/minilzo"
    tmp="$(mktemp -d)"
    echo "  downloading minilzo-2.10..."
    curl -fsSL "$MINILZO_TARBALL" -o "$tmp/minilzo.tar.gz"
    tar -xzf "$tmp/minilzo.tar.gz" -C "$tmp"
    cp "$tmp"/minilzo-*/minilzo.c "$tmp"/minilzo-*/minilzo.h \
       "$tmp"/minilzo-*/lzoconf.h "$tmp"/minilzo-*/lzodefs.h \
       "$tmp"/minilzo-*/COPYING "$VENDOR/minilzo/"
    rm -rf "$tmp"
    [ -f "$VENDOR/minilzo/minilzo.c" ] && echo "  done." || { echo "  error: minilzo extract failed" >&2; exit 1; }
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
    # Extract just the .txt, junking internal paths. Prefer unzip (Linux); fall back
    # to python (Windows CI bash often lacks unzip) so this works on every runner.
    if command -v unzip >/dev/null 2>&1; then
        unzip -o -j "$tmp/nadeo.zip" '*NadeoImporterMaterialLib.txt' -d "$VENDOR/nadeo" >/dev/null
    else
        PY="$(command -v python3 || command -v python || true)"
        [ -n "$PY" ] || { echo "  error: need 'unzip' or 'python' to extract the lib" >&2; rm -rf "$tmp"; exit 1; }
        "$PY" - "$tmp/nadeo.zip" "$VENDOR/nadeo" <<'PY'
import sys, zipfile, os
zf, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zf) as z:
    for n in z.namelist():
        if n.replace("\\", "/").endswith("NadeoImporterMaterialLib.txt"):
            with z.open(n) as s, open(os.path.join(dest, "NadeoImporterMaterialLib.txt"), "wb") as o:
                o.write(s.read())
            break
PY
    fi
    rm -rf "$tmp"
    [ -f "$MATLIB" ] && echo "  done." || { echo "  error: txt not found in zip" >&2; exit 1; }
fi

echo ""
echo "All deps ready."
