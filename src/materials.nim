## Material binding for the .Mesh.Gbx writer. Parses the sibling `.MeshParams.xml`
## (each `<Material Name= Link= PhysicsId= [GameplayId=] />`) and maps the PhysicsId
## / GameplayId names to the byte enum values NadeoImporter stores in the
## CPlugMaterialUserInst node. Confirmed by differential RE: PhysicsId="Asphalt" ->
## SurfacePhysicId 16, "Dirt" -> 6 (= MaterialId enum index); Link + Name pass
## through verbatim. Enum orders transcribed from gbx-net (CPlugSurface.MaterialId,
## CPlugMaterialUserInst.GameplayId). See memory `materials-binding`.

import std/[xmlparser, xmltree, strutils, streams]

# CPlugSurface.MaterialId — index is the on-wire SurfacePhysicId byte.
const materialIds = [
  "Concrete", "Pavement", "Grass", "Ice", "Metal", "Sand", "Dirt",
  "Turbo_Deprecated", "DirtRoad", "Rubber", "SlidingRubber", "Test", "Rock",
  "Water", "Wood", "Danger", "Asphalt", "WetDirtRoad", "WetAsphalt",
  "WetPavement", "WetGrass", "Snow", "ResonantMetal", "GolfBall", "GolfWall",
  "GolfGround", "Turbo2_Deprecated", "Bumper_Deprecated", "NotCollidable",
  "FreeWheeling_Deprecated", "TurboRoulette_Deprecated", "WallJump", "MetalTrans",
  "Stone", "Player", "Trunk", "TechLaser", "SlidingWood", "PlayerOnly", "Tech",
  "TechArmor", "TechSafe", "OffZone", "Bullet", "TechHook", "TechGround",
  "TechWall", "TechArrow", "TechHook2", "Forest", "Wheat", "TechTarget",
  "PavementStair", "TechTeleport", "Energy", "TechMagnetic",
  "TurboTechMagnetic_Deprecated", "Turbo2TechMagnetic_Deprecated",
  "TurboWood_Deprecated", "Turbo2Wood_Deprecated",
  "FreeWheelingTechMagnetic_Deprecated", "FreeWheelingWood_Deprecated",
  "TechSuperMagnetic", "TechNucleus", "TechMagneticAccel", "MetalFence",
  "TechGravityChange", "TechGravityReset", "RubberBand", "Gravel",
  "Hack_NoGrip_Deprecated", "Bumper2_Deprecated", "NoSteering_Deprecated",
  "NoBrakes_Deprecated", "RoadIce", "RoadSynthetic", "Green", "Plastic",
  "DevDebug", "Free3", "XXX_Null"]

# CPlugMaterialUserInst.GameplayId — index is the on-wire SurfaceGameplayId byte.
const gameplayIds = [
  "None", "Turbo", "Turbo2", "TurboRoulette", "FreeWheeling", "NoGrip",
  "NoSteering", "ForceAcceleration", "Reset", "SlowMotion", "Bumper", "Bumper2",
  "Fragile", "NoBrakes", "Cruise", "ReactorBoost_Oriented",
  "ReactorBoost2_Oriented", "VehicleTransform_Reset", "VehicleTransform_CarSnow",
  "VehicleTransform_CarRally", "VehicleTransform_CarDesert"]

# The Nadeo material catalog, embedded at COMPILE time (staticRead) so the binary
# has no runtime dependency on the .txt. Each material's ordered DUvLayer list
# determines the per-material vertex format (decl list / tangents) — see
# `uvLayersForLink` and memory `one-layer-vertex-format`.
const libText = staticRead("../vendor/nadeo/NadeoImporterMaterialLib.txt")

proc uvLayersForLink*(link: string): seq[string] =
  ## Ordered DUvLayer layer names for a stock material `Link` (e.g. RoadTech ->
  ## @["BaseMaterial","Lightmap"], Grass -> @["Lightmap"]). Empty seq if the Link
  ## is not in the lib. The lib has only 1- and 2-layer materials.
  var inBlock = false
  for rawLine in libText.splitLines():
    let line = rawLine.strip()
    if line.startsWith("DMaterial("):
      let rp = line.find(')')
      inBlock = rp > 0 and line[len("DMaterial(") ..< rp] == link
    elif inBlock and line.startsWith("DUvLayer"):
      let lp = line.find('(')
      let rp = line.find(')')
      if lp >= 0 and rp > lp:
        let inner = line[lp+1 ..< rp]          # e.g. "BaseMaterial\t, 0"
        let comma = inner.find(',')
        result.add (if comma >= 0: inner[0 ..< comma] else: inner).strip()

type MeshMaterial* = object
  name*: string        ## FBX material name -> CPlugMaterialUserInst MaterialName
  link*: string        ## stock material name -> Link
  physicsId*: uint8    ## SurfacePhysicId (MaterialId enum index)
  gameplayId*: uint8   ## SurfaceGameplayId (GameplayId enum index)
  uvLayers*: seq[string] ## ordered DUvLayer names from the lib (drives vertex format)

proc enumIndex(table: openArray[string], name, what: string): uint8 =
  for i, n in table:
    if n == name: return uint8(i)
  raise newException(ValueError, "unknown " & what & " '" & name & "'")

proc surfacePhysicId*(physicsId: string): uint8 =
  ## Map a MeshParams PhysicsId name (e.g. "Asphalt") to its MaterialId byte.
  enumIndex(materialIds, physicsId, "PhysicsId")

proc parseMeshParams*(path: string): seq[MeshMaterial] =
  ## Parse `<MeshParams><Materials><Material .../></Materials></MeshParams>`.
  let s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "cannot open " & path)
  defer: s.close()
  let root = parseXml(s)
  for mats in root.findAll("Materials"):
    for m in mats.findAll("Material"):
      let phys = m.attr("PhysicsId")
      let gp = m.attr("GameplayId")
      let link = m.attr("Link")
      result.add MeshMaterial(
        name: m.attr("Name"),
        link: link,
        physicsId: (if phys.len > 0: surfacePhysicId(phys) else: 0'u8),
        gameplayId: (if gp.len > 0: enumIndex(gameplayIds, gp, "GameplayId") else: 0'u8),
        uvLayers: uvLayersForLink(link))

proc defaultMaterials*(): seq[MeshMaterial] =
  ## The fixture default (Mat0 -> PlatformTech / Asphalt) when no MeshParams exists.
  @[MeshMaterial(name: "Mat0", link: "PlatformTech",
                 physicsId: surfacePhysicId("Asphalt"), gameplayId: 0'u8,
                 uvLayers: uvLayersForLink("PlatformTech"))]

type ItemParams* = object
  author*: string         ## <Item AuthorName=> -> collector ident author
  collection*: string     ## <Item Collection=> -> collector ident collection
  itemType*: string       ## <Item Type=> (e.g. "StaticObject")
  meshParamsLink*: string ## <MeshParamsLink File=> (sibling .MeshParams.xml)

proc parseItemParams*(path: string): ItemParams =
  ## Parse the `<Item AuthorName= Collection= Type=>` root + `<MeshParamsLink File=>`.
  let s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "cannot open " & path)
  defer: s.close()
  let root = parseXml(s)
  result.author = root.attr("AuthorName")
  result.collection = root.attr("Collection")
  result.itemType = root.attr("Type")
  for link in root.findAll("MeshParamsLink"):
    result.meshParamsLink = link.attr("File")
    break
