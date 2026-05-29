# tests

## fixtures/ (gitignored)

A complete NadeoImporter **input set** for golden-file testing:

| file | role |
|---|---|
| `CrownJewel_Tile.fbx` | a small (16 KB), single-mesh / single-material FM4-derived tile |
| `CrownJewel_Tile.MeshParams.xml` | maps the mesh material to the stock `PlatformTech` Nadeo material (no texture dependency) |
| `CrownJewel_Tile.Item.xml` | minimal static-object item referencing the MeshParams |

`fixtures/` is **gitignored**: the `.fbx` is FM4-derived geometry (Turn 10 / Microsoft),
so we don't commit it to a public MIT repo. It's reproducible from the forzamania
`working/fbx_smoketest/` output, or swap in any single-material FBX of your own.

## Generating the golden output (via Steam Proton) — WORKING RECIPE

`NadeoImporter.exe` is Windows-only. We drive **Proton 11's bundled wine
directly** against an existing, fully set-up TM working prefix — the
**forzamania** non-Steam prefix (`compatdata/3529941548`), which already has the
`Documents/Trackmania/Work` tree. (NOT the TM2020 prefix `2225070` — it
spam-launches under Proton because of the Ubisoft launcher. And NadeoImporter's
own non-Steam shortcut, signed appid `-1243636708` = unsigned `3051330588`, has
never been launched so it has no prefix.)

The importer resolves its path arg relative to `<userdir>/Work/`, reads source
there, and writes compiled `.Gbx` to the mirrored path under `<userdir>/Items/`
(`:user:\Items\...`). Pass leading-slash relative paths.

```sh
S="$HOME/.steam/debian-installation"
PROTON="$S/steamapps/common/Proton 11.0"
PFX="$S/steamapps/compatdata/3529941548/pfx"          # forzamania prefix
EXE="/run/media/paths/SSS-Core/python projects/forzamania-release/tools/NadeoImporter.exe"
WORK="$PFX/drive_c/users/steamuser/Documents/Trackmania/Work/Items/freeporter-test"

mkdir -p "$WORK" && cp tests/fixtures/CrownJewel_Tile.* "$WORK/"

export WINEPREFIX="$PFX"
export LD_LIBRARY_PATH="$PROTON/files/lib64:$PROTON/files/lib:$LD_LIBRARY_PATH"
export WINEDLLPATH="$PROTON/files/lib64/wine:$PROTON/files/lib/wine"
export PATH="$PROTON/files/bin:$PATH"
export WINEDEBUG="-all"
cd "$WORK"
wine "$EXE" Mesh /Items/freeporter-test/CrownJewel_Tile.fbx
wine "$EXE" Item /Items/freeporter-test/CrownJewel_Tile.Item.xml
```

Outputs land in `<userdir>/Items/freeporter-test/` as lowercase `.gbx`; copy to
`tests/golden/` with canonical `.Gbx` casing. Already captured here:

| golden | bytes | class id | notes |
|---|---|---|---|
| `CrownJewel_Tile.Mesh.Gbx`  | 1608 | `0x090BB000` CPlugSolid2Model | LZO-compressed body |
| `CrownJewel_Tile.Shape.Gbx` |  491 | CPlugSurface | collision |
| `CrownJewel_Tile.Item.Gbx`  | 2079 | `0x2E002000` CGameItemModel | LZO-compressed body |

Header magic is `GBX` + u16 version `6` + flags `BUCR` (Binary / ref-table
Uncompressed / body **C**ompressed / 'R'). Our Nim output gets diffed against
these once the writers exist.

See forzamania `src/nadeo_runner.py` for the path-handling we mirror.
