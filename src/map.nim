## .Map.Gbx item placement — the native replacement for blendermania-dotnet's
## `place-objects-on-map` (docs/map-gbx-builder.md). Consumes the SAME JSON payload
## forzamania already writes (map_composer.py), so swapping the binary needs no
## change upstream.
##
## Phase 1 (this pass): parse the JSON config, resolve the output path exactly as
## blendermania-dotnet does, and emit a generated grass-safe void map there (reusing
## src/seedmap.nim). Items are parsed and counted but not yet placed — anchored-object
## emission into chunk 0x03043040 is Phase 2.
##
## Deliberate divergence from blendermania-dotnet's CleanItems (which clears the
## embedded data): our void seed embeds the GrassRemover def in chunk 0x03043054, and
## generating from the pristine seed each run already gives a clean slate, so we KEEP
## 0x054 (grass stays removed) and only add items. Items load from the user's local
## Items/ folder by path (how forzamania's maps already work); real zip-embedding for
## shareable maps is a later pass.

import std/[json, os, strutils]
import gbx
import seedmap

type
  Vec3* = object
    x*, y*, z*: float32
  PlacedItem* = object
    name*: string         ## ident path, Items/-relative (e.g. "Forzamania/Alps/X.Item.Gbx")
    path*: string         ## absolute source .Item.Gbx (for embedding; unused in Phase 1)
    position*: Vec3
    rotation*: Vec3       ## yaw/pitch/roll, radians — passed through verbatim
    pivot*: Vec3
  MapConfig* = object
    mapPath*: string
    items*: seq[PlacedItem]
    shouldOverwrite*: bool
    mapSuffix*: string
    cleanItems*: bool
    env*: string

proc getVec3(n: JsonNode): Vec3 =
  ## A {"X","Y","Z"} object -> Vec3; missing/!object -> zero (matches GBX.NET defaults).
  if n == nil or n.kind != JObject: return Vec3()
  Vec3(x: n{"X"}.getFloat().float32,
       y: n{"Y"}.getFloat().float32,
       z: n{"Z"}.getFloat().float32)

proc parseConfig*(path: string): MapConfig =
  ## Parse the forzamania/blendermania-dotnet payload. Raises on malformed JSON
  ## (caller maps that to the invalid-payload exit code).
  let j = parseJson(readFile(path))
  result.mapPath = j{"MapPath"}.getStr()
  result.shouldOverwrite = j{"ShouldOverwrite"}.getBool(false)
  result.mapSuffix = j{"MapSuffix"}.getStr("_modified")
  result.cleanItems = j{"CleanItems"}.getBool(true)
  result.env = j{"Env"}.getStr("Stadium")
  let items = j{"Items"}
  if items != nil and items.kind == JArray:
    for it in items:
      result.items.add PlacedItem(
        name: it{"Name"}.getStr(),
        path: it{"Path"}.getStr(),
        position: getVec3(it{"Position"}),
        rotation: getVec3(it{"Rotation"}),
        pivot: getVec3(it{"Pivot"}))

proc outputPath*(cfg: MapConfig): string =
  ## Mirror blendermania-dotnet's NewPath logic: overwrite -> MapPath as-is; otherwise
  ## insert MapSuffix before the .Map.Gbx (e.g. "X.Map.Gbx" -> "X_modified.Map.Gbx").
  if cfg.shouldOverwrite: return cfg.mapPath
  var suffix = cfg.mapSuffix.strip()
  if suffix.len == 0: suffix = "_modified"
  let sf = splitFile(cfg.mapPath)          # dir / "X.Map" / ".Gbx"
  var fn: string
  if ".map" in sf.name.toLowerAscii:        # "X.Map" -> "X" + suffix + ".Map"
    fn = splitFile(sf.name).name & suffix & ".Map"
  else:
    fn = sf.name & suffix
  result = sf.dir / (fn & sf.ext)

proc mapNameFor(outPath: string): string =
  ## Map display name from the output filename: "X.Map.Gbx" -> "X".
  splitFile(splitFile(outPath).name).name

# --- chunk 0x03043040 (anchored objects), authored from the RE'd v7 template
# (memory: map-item-placement-re). Items are INLINE nodes inside an encapsulated
# block (so num-nodes stays unchanged); the encapsulation resets the Id heap, so
# we emit the id-version once before the first ident. ---

const
  cidAnchoredObjects = 0x03043040'u32   # CGameCtnChallenge anchored-objects chunk
  classAnchoredObject = 0x03101000'u32  # CGameCtnAnchoredObject node class
  chunkAnchoredObject = 0x03101002'u32  # its 0x002 chunk
  skipMarker          = 0x534B4950'u32  # "PIKS" skippable-chunk marker
  nodeEnd             = 0xFACADE01'u32  # inline-node terminator
  deprecVersion       = 10'u32          # WriteListNodeRef_deprec version
  anchoredObjVersion  = 7'u32           # chunk 0x03101002 version (TM2020 today)
  chunkVersion        = 7'u32           # chunk 0x03043040 version (TM2020 today)
  collectionStadium   = 26'u32          # Id(26) = Stadium2020
  # Author recorded in each placement ident. Items resolve by PATH; a mismatch
  # vs the item file's real author is cosmetic (a load popup) but still loads.
  # Verify in-game whether this needs to match the item's author. (old_Alps used
  # "Blendermania"; we brand ours "freeporter".)
  placementAuthor     = "freeporter"

proc putAnchoredObject(w: var GbxWriter, it: PlacedItem, first: bool) =
  w.putU32(classAnchoredObject)
  w.putU32(chunkAnchoredObject)
  w.putU32(anchoredObjVersion)
  if first: w.putI32(3)                       # id-version, once per encapsulation
  # ident {Id = item path ('\' seps), Collection = Stadium2020, Author}
  w.putIdString(it.name.replace("/", "\\"))
  w.putIdLiteral(collectionStadium)
  w.putIdString(placementAuthor)
  # YawPitchRoll vec3 (rotation passed through verbatim)
  w.putF32(it.rotation.x); w.putF32(it.rotation.y); w.putF32(it.rotation.z)
  w.putU8(0); w.putU8(0); w.putU8(0)          # BlockUnitCoord byte3
  w.putIdEmpty()                              # AnchorTreeId = ""
  w.putF32(it.position.x); w.putF32(it.position.y); w.putF32(it.position.z)
  w.putI32(-1)                                # WaypointSpecialProperty = null
  w.putU16(0)                                 # Flags (no PackDesc)
  w.putF32(it.pivot.x); w.putF32(it.pivot.y); w.putF32(it.pivot.z)
  w.putF32(0.0'f32)                           # Scale (GBX.NET default; game = 1.0)
  w.putU32(nodeEnd)

proc buildAnchoredObjectsChunk(items: seq[PlacedItem]): seq[byte] =
  ## The full skippable chunk: id + PIKS + size + [version + encapsulated payload].
  var enc = initGbxWriter()
  enc.putU32(deprecVersion)
  enc.putU32(uint32(items.len))
  for i, it in items:
    putAnchoredObject(enc, it, first = (i == 0))
  # v7 trailing arrays: 5 empty, then snappedOnIndices = N x -1 (nothing snapped).
  for _ in 0 ..< 5: enc.putU32(0)
  enc.putU32(uint32(items.len))
  for _ in 0 ..< items.len: enc.putI32(-1)

  var data = initGbxWriter()
  data.putU32(chunkVersion)
  data.putU32(0'u32)                          # WriteEncapsulated leading 0
  data.putU32(uint32(enc.buf.len))            # encapsulated length
  data.putBytes(enc.buf)

  var chunk = initGbxWriter()
  chunk.putU32(cidAnchoredObjects)
  chunk.putU32(skipMarker)
  chunk.putU32(uint32(data.buf.len))
  chunk.putBytes(data.buf)
  result = chunk.buf

proc buildMapBody(items: seq[PlacedItem]): seq[byte] =
  ## The shipped (already-stripped) seed body with the empty 0x040 segment replaced by
  ## our authored anchored objects; everything else (incl. the 0x054 GrassRemover embed)
  ## is copied verbatim.
  let (_, body) = loadSeed()
  let chunk040 = buildAnchoredObjectsChunk(items)
  result = @[]
  for s in segments(body):
    if s.chunkId == cidAnchoredObjects:
      result.add chunk040
    else:
      result.add body[s.lo ..< s.hi]

proc buildMap*(cfg: MapConfig): string =
  ## Emit the map for `cfg` and return the path written: a generated grass-safe void
  ## map with a unique UID/name and the config's items placed (referenced from the
  ## local Items/ folder by path).
  let outPath = outputPath(cfg)
  let name = mapNameFor(outPath)
  let body = buildMapBody(cfg.items)
  saveGbx(outPath, seedMapInfoNamed(uidFromName(name), name), body)
  return outPath
