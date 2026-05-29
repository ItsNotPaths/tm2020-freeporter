version       = "0.1.0"
author        = "ItsNotPaths"
description   = "Native Linux replacement for NadeoImporter: Blender mesh -> TM2020 .Item.Gbx"
license       = "MIT"
srcDir        = "src"
namedBin["nadeo_freeporter"] = "nadeo-freeporter"

requires "nim >= 2.0.0"

# Self-contained CLI — no third-party build deps. gbx-net under vendor/ is a
# read-only reference for the GBX chunk formats, not linked. Build with
# `nimble build` or ./release.sh --local.
