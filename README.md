# nadeo-freeporter

Native Linux replacement for `NadeoImporter.exe` *and* blendermania's .NET map tool —
turns a Blender-exported FBX into TrackMania 2020 `.Mesh.Gbx` / `.Shape.Gbx` / `.Item.Gbx`,
and places items into a `.Map.Gbx`, no Wine. CLI, written in Nim.

## Build

```sh
./download-deps.sh      # vendor ufbx, gbx-net (reference), material lib -> vendor/
nimble build            # -> ./nadeo-freeporter
```

## Use

```sh
nadeo-freeporter mesh  <file.fbx>   # -> .Mesh.Gbx + .Shape.Gbx (reads sibling .MeshParams.xml)
nadeo-freeporter shape <file.fbx>   # -> .Shape.Gbx only
nadeo-freeporter item  <file.fbx>   # -> .Item.Gbx (reads sibling .Item.xml + .MeshParams.xml)
nadeo-freeporter seedmap <out.Gbx>  # -> blank grass-safe void .Map.Gbx
nadeo-freeporter map   <cfg.json>   # -> place items into a .Map.Gbx (blendermania-dotnet payload)
nadeo-freeporter gbx   <file.Gbx>   # debug: parse + dump a .Gbx
```

`map` also accepts the `place-objects-on-map` verb (drop-in for blendermania-dotnet).

## Tests

```sh
nim c -r tests/shape_bytediff.nim   # } each asserts our output is byte-identical to
nim c -r tests/mesh_bytediff.nim    # } the real NadeoImporter goldens on a 13-fixture
nim c -r tests/item_bytediff.nim    # } ladder (tests/gen/golden/*, gitignored)
```

Reference: gbx-net (`vendor/gbx-net`, C#, not linked). FBX via ufbx. Goldens captured from
real NadeoImporter under Proton — see `tests/README.md`.
