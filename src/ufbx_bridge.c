#include "ufbx_bridge.h"
#include "ufbx.h"
#include <string.h>

fp_fbx_summary fp_fbx_summarize(const char *path)
{
    fp_fbx_summary s;
    memset(&s, 0, sizeof(s));

    ufbx_error err;
    ufbx_scene *scene = ufbx_load_file(path, NULL, &err);
    if (!scene) {
        s.ok = 0;
        size_t n = err.description.length;
        if (n >= sizeof(s.error)) n = sizeof(s.error) - 1;
        if (err.description.data) memcpy(s.error, err.description.data, n);
        s.error[n] = '\0';
        return s;
    }

    s.ok = 1;
    s.meshes = scene->meshes.count;
    s.materials = scene->materials.count;
    for (size_t i = 0; i < scene->meshes.count; i++) {
        ufbx_mesh *m = scene->meshes.data[i];
        s.vertices += m->num_vertices;
        s.faces += m->num_faces;
        s.triangles += m->num_triangles;
    }

    ufbx_free_scene(scene);
    return s;
}
