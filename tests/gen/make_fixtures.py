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


def new_mesh_object(name, verts, faces, uvs=None):
    """Create a mesh object from explicit verts (list of (x,y,z)) and faces
    (list of index tuples). uvs: optional per-loop (u,v) list matching the
    flattened face-corner order."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    # UV layer (NadeoImporter expects at least the base UV).
    uv_layer = mesh.uv_layers.new(name="UVMap")
    if uvs is not None:
        for i, loop in enumerate(mesh.loops):
            uv_layer.data[i].uv = uvs[i]

    return obj


def assign_material(obj, mat_name):
    mat = bpy.data.materials.new(mat_name)
    obj.data.materials.append(mat)


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


def main():
    d = out_dir()
    os.makedirs(d, exist_ok=True)
    fixture_triangle(d)
    fixture_two_triangles(d)
    fixture_unit_cube(d)
    fixture_triangle_shifted(d)
    print("FIXTURES_WRITTEN:", d)


if __name__ == "__main__":
    main()
