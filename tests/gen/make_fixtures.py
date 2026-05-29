"""Generate a ladder of minimal FBX fixtures for differential RE of the GBX
format. Run headless with the Steam Blender 3.5:

  BL=".../SteamLibrary/steamapps/common/Blender/blender/blender"
  "$BL" --background --factory-startup --python tests/gen/make_fixtures.py -- tests/gen/out

The "--" separates Blender args from ours; the single positional arg is the
output directory. Each fixture is a controlled mutation of the previous so that
diffing the resulting .Mesh/.Shape.Gbx (decompressed) against real NadeoImporter
output labels one field at a time. Everything is built by hand (no primitives
that add hidden geometry) so every vertex/index is predictable.
"""

import bpy
import bmesh
import sys
import os
import math


def out_dir():
    argv = sys.argv
    if "--" in argv:
        tail = argv[argv.index("--") + 1:]
        if tail:
            return tail[0]
    return "tests/gen/out"


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_lightmap_uv(mesh):
    """NadeoImporter REQUIRES every material to have >= 2 UV layers
    (BaseMaterial + LightMap) or mesh import fails: "not enough UvLayers for
    material (1 < 2)". This was THE cause of our earlier exit-1 rejections.
    Transcribed from forzamania scripts/blender_export.py::_add_lightmap_uv:
    lay every face out in its own cell of a GxG grid (G=ceil(sqrt(faces))) so
    the lightmap is non-overlapping per face. Pure arithmetic, no packer."""
    import math
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


def new_mesh_object(name, verts, faces, uvs=None, smooth=False):
    """Create a mesh object from explicit verts (list of (x,y,z)) and faces
    (list of index tuples). uvs: optional per-loop (u,v) list matching the
    flattened face-corner order. smooth=True shades the mesh smooth (averaged
    per-vertex normals) instead of flat per-face normals."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    mesh.from_pydata(verts, [], faces)
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    mesh.update()

    # Base UV layer — must be named "BaseMaterial" (NadeoImporter looks for it
    # at index 0 for diffuse). Then add the required 2nd LightMap layer.
    uv_layer = mesh.uv_layers.new(name="BaseMaterial")
    if uvs is not None:
        for i, loop in enumerate(mesh.loops):
            uv_layer.data[i].uv = uvs[i]

    add_lightmap_uv(mesh)
    # Leave BaseMaterial active (exporter writes the active layer first).
    for i, layer in enumerate(mesh.uv_layers):
        if layer.name == "BaseMaterial":
            mesh.uv_layers.active_index = i
            break

    return obj


def assign_material(obj, mat_name):
    mat = bpy.data.materials.new(mat_name)
    obj.data.materials.append(mat)


def write_meshparams(d, stem, materials):
    """Write <stem>.MeshParams.xml next to the fbx. materials: list of
    (Name, Link, PhysicsId). run_nadeo.sh copies this if present, else writes a
    default Mat0->PlatformTech/Asphalt. Lets material fixtures vary the binding."""
    rows = "\n".join(
        '        <Material Name="%s" Link="%s" PhysicsId="%s" />' % (n, l, p)
        for (n, l, p) in materials)
    xml = ('<?xml version="1.0" ?>\n'
           '<MeshParams Scale="1.0" MeshType="Static" Collection="Stadium" '
           'FbxFile="%s.fbx">\n    <Materials>\n%s\n    </Materials>\n'
           '    <Lights/>\n</MeshParams>\n') % (stem, rows)
    with open(os.path.join(d, stem + ".MeshParams.xml"), "w") as f:
        f.write(xml)


def export_fbx(path):
    # These flags are copied verbatim from forzamania's known-good exporter
    # (forzamania/scripts/blender_export.py). NadeoImporter is picky about axis
    # system (Y-up, -Z forward), units, normals/tangents, and material binding;
    # bake_space_transform=True bakes the Blender(Z-up)->Nadeo(Y-up) conversion
    # into the geometry. Do NOT change without re-verifying the importer accepts
    # the output.
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


def fixture_triangle(d):
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("tri", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "01_triangle.fbx"))


def fixture_two_triangles(d):
    reset_scene()
    verts = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)]
    faces = [(0, 1, 2), (1, 3, 2)]
    uvs = [(0, 0), (1, 0), (0, 1), (1, 0), (1, 1), (0, 1)]
    obj = new_mesh_object("quad2tri", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "02_two_triangles.fbx"))


def fixture_unit_cube(d):
    reset_scene()
    # 8 corners, 12 triangles, explicit so order is known.
    v = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
         (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]
    f = [(0, 1, 2), (0, 2, 3),   # bottom
         (4, 6, 5), (4, 7, 6),   # top
         (0, 5, 1), (0, 4, 5),   # front
         (1, 6, 2), (1, 5, 6),   # right
         (2, 7, 3), (2, 6, 7),   # back
         (3, 4, 0), (3, 7, 4)]   # left
    uvs = []
    for face in f:
        for _ in face:
            uvs.append((0.0, 0.0))
    obj = new_mesh_object("cube", v, f, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "03_unit_cube.fbx"))


def fixture_triangle_shifted(d):
    # Same as the triangle but vertex 1 moved +1 in X — isolates which output
    # float is that vertex's X coordinate.
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (2.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("tri", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "04_triangle_shifted.fbx"))


def fixture_smooth_cube(d):
    # Same geometry as 03_unit_cube but SMOOTH-shaded — averaged per-vertex
    # normals instead of per-face. Tests whether NadeoImporter shares render
    # verts when smoothing makes corner normals match, or still explodes (3
    # verts/triangle) because the per-triangle lightmap atlas forces unique UVs.
    reset_scene()
    v = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
         (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]
    f = [(0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6),
         (0, 5, 1), (0, 4, 5), (1, 6, 2), (1, 5, 6),
         (2, 7, 3), (2, 6, 7), (3, 4, 0), (3, 7, 4)]
    uvs = [(0.0, 0.0) for face in f for _ in face]
    obj = new_mesh_object("scube", v, f, uvs, smooth=True)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "05_smooth_cube.fbx"))


def fixture_tilted_triangle(d):
    # A triangle whose normal is NOT axis-aligned (vertex 2 lifted in Z), with
    # real UVs — exercises the general UV-gradient tangent path beyond the
    # axis-aligned cases the cube covered.
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 1.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("tilt", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "06_tilted_triangle.fbx"))


def fixture_tilted_degenerate(d):
    # Same tilted geometry as 06 but DEGENERATE UVs (all 0,0) — exercises the
    # geometric tangent fallback for a non-axis-aligned normal.
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 1.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (0.0, 0.0), (0.0, 0.0)]
    obj = new_mesh_object("tiltdeg", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "07_tilted_degenerate.fbx"))


def fixture_tri_fan(d, n, fname):
    # n independent triangles spaced along X — tests the lightmap grid growth
    # (G=ceil(sqrt(n))) and row packing for non-square triangle counts.
    reset_scene()
    verts = []
    faces = []
    uvs = []
    for i in range(n):
        base = len(verts)
        x = i * 1.5
        verts += [(x, 0.0, 0.0), (x + 1.0, 0.0, 0.0), (x, 1.0, 0.0)]
        faces.append((base, base + 1, base + 2))
        uvs += [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("fan%d" % n, verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, fname))


def fixture_mat_link(d):
    # Triangle (real UVs) but Link=RoadTech instead of PlatformTech — isolates the
    # Link string in the material node (vs 01_triangle).
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("tri", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "11_mat_link.fbx"))
    write_meshparams(d, "11_mat_link", [("Mat0", "RoadTech", "Asphalt")])


def fixture_mat_physics(d):
    # Triangle but PhysicsId=Dirt instead of Asphalt — isolates the SurfacePhysicId
    # byte (MaterialId enum: Dirt=6 vs Asphalt=16) in both the Mesh material node
    # AND the Shape collision (per-tri surfaceIndex + tail U02).
    reset_scene()
    verts = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    faces = [(0, 1, 2)]
    uvs = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    obj = new_mesh_object("tri", verts, faces, uvs)
    assign_material(obj, "Mat0")
    export_fbx(os.path.join(d, "12_mat_physics.fbx"))
    write_meshparams(d, "12_mat_physics", [("Mat0", "PlatformTech", "Dirt")])


def fixture_two_materials(d):
    # A quad split into two triangles, each with its OWN material (different Link
    # AND PhysicsId) — maps how multiple materials grow the ShadedGeom list, the
    # customMaterials array, and whether triangles get grouped/reordered.
    reset_scene()
    verts = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)]
    faces = [(0, 1, 2), (1, 3, 2)]
    uvs = [(0, 0), (1, 0), (0, 1), (1, 0), (1, 1), (0, 1)]
    obj = new_mesh_object("quad2", verts, faces, uvs)
    m0 = bpy.data.materials.new("Mat0")
    m1 = bpy.data.materials.new("Mat1")
    obj.data.materials.append(m0)
    obj.data.materials.append(m1)
    obj.data.polygons[0].material_index = 0
    obj.data.polygons[1].material_index = 1
    export_fbx(os.path.join(d, "13_two_materials.fbx"))
    write_meshparams(d, "13_two_materials",
                     [("Mat0", "PlatformTech", "Asphalt"),
                      ("Mat1", "RoadTech", "Dirt")])


def main():
    d = out_dir()
    os.makedirs(d, exist_ok=True)
    fixture_triangle(d)
    fixture_two_triangles(d)
    fixture_unit_cube(d)
    fixture_triangle_shifted(d)
    fixture_smooth_cube(d)
    fixture_tilted_triangle(d)
    fixture_tilted_degenerate(d)
    fixture_tri_fan(d, 3, "08_tri3.fbx")
    fixture_tri_fan(d, 5, "09_tri5.fbx")
    fixture_tri_fan(d, 7, "10_tri7.fbx")
    fixture_mat_link(d)
    fixture_mat_physics(d)
    fixture_two_materials(d)
    print("FIXTURES_WRITTEN:", d)


if __name__ == "__main__":
    main()
