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

type MeshMaterial* = object
  name*: string        ## FBX material name -> CPlugMaterialUserInst MaterialName
  link*: string        ## stock material name -> Link
  physicsId*: uint8    ## SurfacePhysicId (MaterialId enum index)
  gameplayId*: uint8   ## SurfaceGameplayId (GameplayId enum index)

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
      result.add MeshMaterial(
        name: m.attr("Name"),
        link: m.attr("Link"),
        physicsId: (if phys.len > 0: surfacePhysicId(phys) else: 0'u8),
        gameplayId: (if gp.len > 0: enumIndex(gameplayIds, gp, "GameplayId") else: 0'u8))

proc defaultMaterials*(): seq[MeshMaterial] =
  ## The fixture default (Mat0 -> PlatformTech / Asphalt) when no MeshParams exists.
  @[MeshMaterial(name: "Mat0", link: "PlatformTech",
                 physicsId: surfacePhysicId("Asphalt"), gameplayId: 0'u8)]
