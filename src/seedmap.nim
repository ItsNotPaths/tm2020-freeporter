## .Map.Gbx (CGameCtnChallenge, class 0x03043000) seed emitter.
##
## First pass of the native blendermania-dotnet replacement (docs/map-gbx-builder.md,
## milestone 1): emit a *blank void seed map* that is 1:1 faithful — on the
## decompressed body — to resources/seed-void.Map.Gbx. No items yet; item
## embedding (0x03043054) and anchored-object placement (0x03043040) are later passes.
##
## Approach (minimal, droppable): the real seed is embedded at compile time and its
## body decompressed once at runtime, then re-emitted via the shared GBX core
## (src/gbx.nim — same loadGbx/saveGbx the item builder uses). The body is tiled
## into `Segment`s: every *skippable* top-level chunk (lightmaps, block-data-adjacent
## skippables, embedded zip, etc.) is its own named, individually-disable-able slice;
## everything between them is opaque "structural" passthrough. With all segments
## enabled the rebuilt body is byte-identical to the seed (the faithful pass); to
## experiment with dropping a chunk, flip its `enabled` to false (see dropByDefault).
##
## Note: the *file* is not byte-identical to the seed — we recompress with LZO1X-1
## while Nadeo uses LZO1X-999. Fidelity is on the decompressed body (same as items).

import std/[strutils, os]
import gbx

const SKIP = 0x534B4950'u32          # "PIKS" on disk — the skippable-chunk marker

# The seed map, embedded in the binary. Path is relative to this source file.
const seedBytes = staticRead("../resources/seed-void.Map.Gbx")

# Known *skippable* CGameCtnChallenge chunk ids present in TM2020 maps (from
# vendor/gbx-net/Src/GBX.NET/Engines/Game/CGameCtnChallenge.chunkl). These are the
# only cut points; non-skippable structural chunks (0x00D vehicle, 0x011 params,
# 0x01F block data, …) stay inside opaque passthrough spans, so we never decode them.
const skippableChunks: seq[(uint32, string)] = @[
  (0x03043018'u32, "laps"),
  (0x03043019'u32, "mod"),
  (0x03043029'u32, "password"),
  (0x03043034'u32, "ChallengeDecals"),
  (0x03043036'u32, "realtime thumbnail + comments"),
  (0x03043038'u32, "ChallengeCardEventIds"),
  (0x0304303E'u32, "CarMarksBuffer"),
  (0x03043040'u32, "items / anchored objects"),
  (0x03043042'u32, "author"),
  (0x03043043'u32, "genealogies"),
  (0x03043044'u32, "metadata"),
  (0x03043048'u32, "baked blocks"),
  (0x0304304B'u32, "objectives"),
  (0x0304304F'u32, "0x04F"),
  (0x03043050'u32, "offzones"),
  (0x03043051'u32, "title info"),
  (0x03043052'u32, "deco height"),
  (0x03043053'u32, "bot paths"),
  (0x03043054'u32, "embedded objects (zip)"),
  (0x03043055'u32, "0x055"),
  (0x03043056'u32, "light settings"),
  (0x03043059'u32, "world distortion"),
  (0x0304305A'u32, "0x05A"),
  (0x0304305B'u32, "lightmaps"),
  (0x0304305F'u32, "free blocks"),
  (0x03043060'u32, "0x060"),
  (0x03043062'u32, "MapElemColor"),
  (0x03043063'u32, "AnimPhaseOffset"),
  (0x03043065'u32, "foreground pack desc"),
  (0x03043068'u32, "MapElemLmQuality"),
  (0x03043069'u32, "macroblock instances"),
  (0x0304306B'u32, "light settings 2"),
  (0x0304306C'u32, "color palette"),
]

## Chunks stripped from the generated seed by default.
##
## Determined empirically by an in-game grass bisection (2026-05-30, fp ladder).
## The void base places a GrassRemover custom block; its no-grass effect needs the
## embedded def 0x03043054 PLUS the chunks below it kept. The proven-safe line is
## fp12's config: drop ONLY these 12 cosmetic/lighting/map-element cache chunks (all
## above 0x054); keep everything from 0x054 down. This was load/save/TMX-publish-safe
## with NO visual change (grass stays removed). Stripping further — into 0x054 or the
## chunks below it — brings the grass back, so we stop here for the default.
## (Bigger cruft like genealogies 0x043 / baked blocks 0x048 sit below 0x054 and are
## NOT stripped by default; a future targeted test could reclaim them if grass-safe.)
const dropByDefault: seq[uint32] = @[
  0x03043069'u32,  # macroblock instances
  0x03043068'u32,  # MapElemLmQuality
  0x03043065'u32,  # foreground pack desc
  0x03043063'u32,  # AnimPhaseOffset
  0x03043062'u32,  # MapElemColor
  0x03043060'u32,  # 0x060
  0x0304305F'u32,  # free blocks
  0x0304305B'u32,  # lightmaps
  0x0304305A'u32,  # 0x05A
  0x03043059'u32,  # world distortion
  0x03043056'u32,  # light settings
  0x03043055'u32,  # 0x055
  # Below 0x054 but verified grass-safe in-game (the "LEAN" probe), so also dropped:
  0x03043048'u32,  # baked blocks  (~266 KB compressed)
  0x03043043'u32,  # genealogies   (~2 MB decompressed cruft)
  0x03043044'u32,  # metadata
]

type Segment* = object
  label*: string          # human label, e.g. "lightmaps"
  chunkId*: uint32        # 0 for structural passthrough spans
  lo*, hi*: int           # [lo, hi) byte range in the decompressed body
  skippable*: bool        # true for a droppable skippable-chunk segment
  enabled*: bool          # false -> excluded from the emitted body

proc rdU32(b: openArray[byte], i: int): uint32 {.inline.} =
  uint32(b[i]) or (uint32(b[i+1]) shl 8) or
    (uint32(b[i+2]) shl 16) or (uint32(b[i+3]) shl 24)

proc labelFor(cid: uint32): string =
  for (id, name) in skippableChunks:
    if id == cid: return name
  "0x" & toHex(cid)

proc isSkippable(cid: uint32): bool =
  for (id, _) in skippableChunks:
    if id == cid: return true
  false

proc loadSeed*(): tuple[info: GbxInfo, body: seq[byte]] =
  ## Parse the embedded seed: header + LZO-decompressed body. Reuses src/gbx.nim.
  let raw = cast[seq[byte]](@(seedBytes.toOpenArrayByte(0, seedBytes.len - 1)))
  var r = initGbxReader(raw)
  var info = r.parseHeader()
  let body = r.readBody(info)
  result = (info, body)

proc segments*(body: seq[byte]): seq[Segment] =
  ## Tile the decompressed body: one Segment per known skippable chunk found by its
  ## (chunkId + "PIKS" marker + size) anchor, with opaque structural spans between.
  ## The tiling is contiguous, so concatenating every segment reproduces `body`
  ## exactly; dropping a (skippable) segment removes precisely that chunk's bytes.
  ## All segments come back `enabled`; the body builder applies the drop set.
  var cuts: seq[Segment] = @[]
  var i = 0
  while i + 12 <= body.len:
    # Cheap reject first (the marker fails at almost every position), then validate
    # the chunk id against the known-skippable set and a sane payload size.
    if rdU32(body, i + 4) == SKIP:
      let cid = rdU32(body, i)
      if isSkippable(cid):
        let size = int(rdU32(body, i + 8))
        let total = 12 + size
        if size >= 0 and i + total <= body.len:
          cuts.add Segment(label: labelFor(cid), chunkId: cid, lo: i, hi: i + total,
                           skippable: true, enabled: true)
          i += total
          continue
    inc i
  # Stitch structural spans between the skippable cuts.
  result = @[]
  var pos = 0
  for c in cuts:
    if c.lo > pos:
      result.add Segment(label: "structural", chunkId: 0, lo: pos, hi: c.lo,
                         skippable: false, enabled: true)
    result.add c
    pos = c.hi
  if pos < body.len:
    result.add Segment(label: "structural", chunkId: 0, lo: pos, hi: body.len,
                       skippable: false, enabled: true)

proc buildSeedMapBody*(drop: seq[uint32] = dropByDefault): seq[byte] =
  ## The decompressed map body to emit: every segment concatenated except skippable
  ## chunks whose id is in `drop`. With `drop` empty this is byte-identical to the
  ## seed body. Structural spans (chunkId 0) are always kept.
  let (_, body) = loadSeed()
  result = @[]
  for s in segments(body):
    if s.skippable and s.chunkId in drop: continue
    result.add body[s.lo ..< s.hi]

proc patchUserData*(userData: seq[byte], uid, mapName: string,
                    authorLogin = "", authorNick = "", authorZone = ""): seq[byte] =
  ## Rebuild the header user-data block with a new MapUid + MapName (header chunk
  ## 0x03043003) and, when `authorLogin` is non-empty, a new author across all three
  ## places it lives: the 0x003 ident author Id, the 0x008 AuthorInfo (login/nick/
  ## zone), and the 0x005 community XML (author= / authorzone= and uid/name attrs).
  ## Each touched chunk's directory size is fixed up; everything else is verbatim.
  let rebrand = authorLogin.len > 0
  var r = initGbxReader(userData)
  let n = int(r.readI32())
  var ids: seq[uint32]
  var sizes: seq[int]
  var heavies: seq[bool]
  for _ in 0 ..< n:
    ids.add r.readU32()
    let raw = r.readU32()
    heavies.add (raw and 0x80000000'u32) != 0
    sizes.add int(raw and 0x7FFFFFFF'u32)
  let payloadStart = r.pos
  var payOff: seq[int] = @[]
  block:
    var o = payloadStart
    for k in 0 ..< n: (payOff.add o; o += sizes[k])

  # First pass: capture the OLD uid/name/login/zone so we can rewrite the XML.
  var oldUid, oldName, oldLogin, oldZone: string
  for k in 0 ..< n:
    let pl = userData[payOff[k] ..< payOff[k] + sizes[k]]
    if ids[k] == 0x03043003'u32:
      var c = initGbxReader(pl)
      discard c.readU8(); oldUid = c.readId()
      discard c.readId(); oldLogin = c.readId(); oldName = c.readString()
    elif ids[k] == 0x03043008'u32:
      var c = initGbxReader(pl)
      discard c.readU32(); discard c.readI32()
      discard c.readString()        # login (== oldLogin)
      discard c.readString()        # nickname
      oldZone = c.readString()

  # Second pass: rebuild patched payloads.
  var payloads: seq[seq[byte]] = @[]
  for k in 0 ..< n:
    var pl = userData[payOff[k] ..< payOff[k] + sizes[k]]
    if ids[k] == 0x03043003'u32:
      var c = initGbxReader(pl)
      let ver = c.readU8()
      doAssert c.pos == 1, "unexpected SHeaderCommon layout"
      discard c.readId()            # ident.id (old MapUid)
      let afterUid = c.pos
      discard c.readId()            # ident.collection
      let afterCol = c.pos
      discard c.readId()            # ident.author
      let nameStart = c.pos
      discard c.readString()        # old MapName
      let afterName = c.pos
      var w = initGbxWriter()
      w.putU8(ver)
      w.putI32(3)                   # Id version (uid is the first Id)
      w.putU32(0x40000000'u32); w.putStr(uid)
      if rebrand:
        w.putBytes(pl[afterUid ..< afterCol])    # collection Id verbatim
        w.putU32(0x40000000'u32); w.putStr(authorLogin)  # new author Id (fresh str)
      else:
        w.putBytes(pl[afterUid ..< nameStart])   # collection + author Ids verbatim
      w.putStr(mapName)
      w.putBytes(pl[afterName ..< pl.len])
      pl = w.buf
    elif ids[k] == 0x03043008'u32 and rebrand:
      var c = initGbxReader(pl)
      let verBytes = block: discard c.readU32(); discard c.readI32(); pl[0 ..< c.pos]
      discard c.readString(); discard c.readString(); discard c.readString()
      let extra = c.readString()
      var w = initGbxWriter()
      w.putBytes(verBytes)
      w.putStr(authorLogin); w.putStr(authorNick); w.putStr(authorZone); w.putStr(extra)
      pl = w.buf
    elif ids[k] == 0x03043005'u32 and rebrand:
      var c = initGbxReader(pl)
      var xml = c.readString()
      if oldUid.len > 0: xml = xml.replace(oldUid, uid)
      if oldName.len > 0: xml = xml.replace(oldName, mapName)
      if oldLogin.len > 0: xml = xml.replace(oldLogin, authorLogin)
      if oldZone.len > 0: xml = xml.replace(oldZone, authorZone)
      var w = initGbxWriter(); w.putStr(xml); pl = w.buf
    payloads.add pl

  # Re-emit the directory (with the patched size) then the payloads.
  var w = initGbxWriter()
  w.putI32(int32(n))
  for k in 0 ..< n:
    w.putU32(ids[k])
    var raw = uint32(payloads[k].len)
    if heavies[k]: raw = raw or 0x80000000'u32
    w.putU32(raw)
  for p in payloads:
    w.putBytes(p)
  result = w.buf

proc seedMapInfo*(): GbxInfo =
  ## Header for the emitted map: taken verbatim from the seed (class 0x03043000,
  ## version 6, refTable U, body C, and the user-data block — map name / UID /
  ## thumbnail / author — passed through). numNodes is preserved from the seed; a
  ## seed-only map adds no nodes.
  let (info, _) = loadSeed()
  result = info
  result.bodyCompression = gcCompressed   # always re-emit compressed

proc saveSeedMapGbx*(path: string, drop: seq[uint32] = dropByDefault) =
  ## Write a blank void seed map to `path`, omitting any skippable chunk in `drop`.
  saveGbx(path, seedMapInfo(), buildSeedMapBody(drop))

# Author identity stamped on generated seeds (replaces the eyebo template's author).
const fpLogin* = "freeporter"
const fpNick* = "freeporter"
const fpZone* = "World"

proc seedMapInfoNamed*(uid, mapName: string,
                       login = fpLogin, nick = fpNick, zone = fpZone): GbxInfo =
  ## Like seedMapInfo but with a fresh MapUid + MapName + author (so TM doesn't dedupe,
  ## variants are distinguishable, and the map is branded freeporter, not eyebo).
  result = seedMapInfo()
  result.userData = patchUserData(result.userData, uid, mapName, login, nick, zone)
  result.userDataLen = result.userData.len

proc saveSeedMapGbxNamed*(path: string, drop: seq[uint32], uid, mapName: string,
                          login = fpLogin, nick = fpNick, zone = fpZone) =
  ## Write a seed map with a unique UID/name, freeporter author, and dropped chunks.
  saveGbx(path, seedMapInfoNamed(uid, mapName, login, nick, zone), buildSeedMapBody(drop))

proc uidFromName*(s: string): string =
  ## Deterministic 27-char base64url-ish MapUid derived from a string (no RNG, so
  ## the same name always yields the same UID, but distinct names differ).
  const alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  var h: uint64 = 1469598103934665603'u64        # FNV-1a 64 offset basis
  for c in s: h = (h xor uint64(ord(c))) * 1099511628211'u64
  result = newString(27)
  var x = h
  for i in 0 ..< 27:
    result[i] = alpha[int(x and 63)]
    x = (x shr 5) xor (x * 6364136223846793005'u64)

proc saveSeedMap*(path: string, drop: seq[uint32] = dropByDefault) =
  ## Production generator: emit a stripped, freeporter-branded seed to `path`, with a
  ## MapName from the file stem and a deterministic UID. This is what the CLI calls.
  let name = splitFile(path).name
  saveSeedMapGbxNamed(path, drop, uidFromName(name), name)

proc defaultDrops*(): seq[uint32] = dropByDefault
  ## The production strip set (all skippables except keepChunks). For callers that
  ## want to emit the default-stripped seed with a custom UID/name.
