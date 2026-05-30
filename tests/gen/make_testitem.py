"""Generate ONE comprehensive, easily-verifiable test item for in-game
acceptance testing of nadeo-freeporter vs the real NadeoImporter.

A 3-step ascending staircase (climbs in +Y, rises in +Z), each step a box with
its OWN stock material so the shape is unambiguous in-game:
  - orientation is obvious (clear front/back/up — asymmetric under any rotation)
  - 3 materials (multi-material grouping path) that look visibly different
  - real (non-degenerate) UVs on every face -> no UV-less tangent divergence
  - 3 boxes x 12 tris = 36 triangles (far more than any ladder fixture)

Reuses the known-good helpers transcribed from forzamania's exporter (>=2 UV
layers, axis system, tangents). Run headless with the Steam Blender:

  BL=".../SteamLibrary/steamapps/common/Blender/blender"
  "$BL" --background --factory-startup --python tests/gen/make_testitem.py -- tests/gen/item

Writes <out>/FM_TestStairs.fbx + .MeshParams.xml + .Item.xml.
"""

import bpy
import sys
import os
import math

STEM = "FM_TestStairs"

# Uniform scale applied to all box bounds below (metres). 10x -> a ~20m wide,
# 60m deep, 30m tall staircase (clearly visible in-editor).
SCALE = 10.0

# (step box bounds in Blender Z-up metres, material name, Link, PhysicsId)
# All three Links are standard 2-UV-layer materials (BaseMaterial + Lightmap) so
# the emitted vertex format matches NadeoImporter; they look visibly different
# (tech platform / brown dirt / blue ice) so each step is easy to tell apart.
STEPS = [
    ((-1.0, 1.0), (-3.0, 3.0), (0.0, 1.0), "StepTech", "PlatformTech", "Asphalt"),
    ((-1.0, 1.0), (-1.0, 3.0), (1.0, 2.0), "StepDirt", "RoadDirt", "Dirt"),
    ((-1.0, 1.0), ( 1.0, 3.0), (2.0, 3.0), "StepIce", "RoadIce", "Ice"),
]


def out_dir():
    argv = sys.argv
    if "--" in argv:
        tail = argv[argv.index("--") + 1:]
        if tail:
            return tail[0]
    return "tests/gen/item"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_lightmap_uv(mesh):
    """NadeoImporter REQUIRES a 2nd non-overlapping LightMap UV layer per
    material (else "not enough UvLayers"). One face per GxG grid cell."""
    light = mesh.uv_layers.new(name="LightMap")
    n = len(mesh.polygons)
    if n == 0:
        return
    grid = max(1, math.ceil(math.sqrt(n)))
    cell = 1.0 / grid
    margin = cell * 0.05
    inner = cell - 2 * margin
    for fi, poly in enumerate(mesh.polygons):
        cx = (fi % grid) * cell
        cy = (fi // grid) * cell
        corners = (
            (cx + margin, cy + margin),
            (cx + margin + inner, cy + margin),
            (cx + margin + inner, cy + margin + inner),
            (cx + margin, cy + margin + inner),
        )
        for k, li in enumerate(poly.loop_indices):
            light.data[li].uv = corners[k % 4]


def box_geometry(xr, yr, zr):
    """8 corners + 12 triangles for an axis-aligned box. Returns (verts, tris,
    tri_uvs) where tri_uvs is one (u,v) per triangle corner (non-degenerate).
    Bounds are multiplied by SCALE. Winding is OUTWARD-facing (the earlier
    version was inverted/inside-out)."""
    x0, x1 = xr[0] * SCALE, xr[1] * SCALE
    y0, y1 = yr[0] * SCALE, yr[1] * SCALE
    z0, z1 = zr[0] * SCALE, zr[1] * SCALE
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    # Reversed winding vs the first attempt so every face normal points OUT.
    f = [(0, 2, 1), (0, 3, 2),   # bottom -Z
         (4, 5, 6), (4, 6, 7),   # top +Z
         (0, 1, 5), (0, 5, 4),   # front -Y
         (1, 2, 6), (1, 6, 5),   # right +X
         (2, 3, 7), (2, 7, 6),   # back +Y
         (3, 0, 4), (3, 4, 7)]   # left -X
    # Simple non-degenerate UV per triangle (gives a real tangent frame).
    tri_uv = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    return v, f, tri_uv


def export_fbx(path):
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=False,
        apply_unit_scale=True,
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_tspace=True,
        use_custom_props=False,
        bake_space_transform=True,
        path_mode="STRIP",
        embed_textures=False,
    )


def build():
    reset_scene()
    verts = []
    faces = []
    face_mat = []
    uvs = []          # per-loop, in face order
    for mi, (xr, yr, zr, _name, _link, _phys) in enumerate(STEPS):
        v, f, tri_uv = box_geometry(xr, yr, zr)
        base = len(verts)
        verts += v
        for tri in f:
            faces.append(tuple(base + i for i in tri))
            face_mat.append(mi)
            uvs += tri_uv

    mesh = bpy.data.meshes.new(STEM)
    obj = bpy.data.objects.new(STEM, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    uv_layer = mesh.uv_layers.new(name="BaseMaterial")
    for i, _loop in enumerate(mesh.loops):
        uv_layer.data[i].uv = uvs[i]
    add_lightmap_uv(mesh)
    for i, layer in enumerate(mesh.uv_layers):
        if layer.name == "BaseMaterial":
            mesh.uv_layers.active_index = i
            break

    for (_xr, _yr, _zr, name, _link, _phys) in STEPS:
        obj.data.materials.append(bpy.data.materials.new(name))
    for fi, poly in enumerate(mesh.polygons):
        poly.material_index = face_mat[fi]

    return obj


def write_meshparams(d):
    rows = "\n".join(
        '        <Material Name="%s" Link="%s" PhysicsId="%s" />' % (name, link, phys)
        for (_xr, _yr, _zr, name, link, phys) in STEPS)
    xml = ('<?xml version="1.0" ?>\n'
           '<MeshParams Scale="1.0" MeshType="Static" Collection="Stadium" '
           'FbxFile="%s.fbx">\n    <Materials>\n%s\n    </Materials>\n'
           '    <Lights/>\n</MeshParams>\n') % (STEM, rows)
    with open(os.path.join(d, STEM + ".MeshParams.xml"), "w") as f:
        f.write(xml)


def write_itemparams(d):
    xml = ('<?xml version="1.0" ?>\n'
           '<Item AuthorName="nadeo-freeporter" Collection="Stadium" Type="StaticObject">\n'
           '    <MeshParamsLink File="%s.MeshParams.xml" />\n'
           '    <Phy/>\n    <Vis/>\n'
           '    <GridSnap HStep="0" VStep="0" HOffset="0" VOffset="0" />\n'
           '    <Levitation HStep="0" VStep="0" HOffset="0" VOffset="0" GhostMode="false" />\n'
           '    <Options AutoRotation="false" ManualPivotSwitch="false" NotOnItem="false" OneAxisRotation="false" />\n'
           '    <PivotSnap Distance="0" />\n'
           '</Item>\n') % STEM
    with open(os.path.join(d, STEM + ".Item.xml"), "w") as f:
        f.write(xml)


def main():
    d = out_dir()
    os.makedirs(d, exist_ok=True)
    build()
    export_fbx(os.path.join(d, STEM + ".fbx"))
    write_meshparams(d)
    write_itemparams(d)
    print("TESTITEM_WRITTEN:", os.path.join(d, STEM + ".fbx"))


if __name__ == "__main__":
    main()
