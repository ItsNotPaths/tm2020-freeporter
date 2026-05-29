#include "ufbx_bridge.h"
#include "ufbx.h"
#include <string.h>
#include <stdlib.h>

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

/* Copy the NUL-truncated ufbx error string into a fixed buffer. */
static void copy_error(char *dst, size_t dst_size, ufbx_string src)
{
    size_t n = src.length;
    if (n >= dst_size) n = dst_size - 1;
    if (src.data) memcpy(dst, src.data, n);
    dst[n] = '\0';
}

/* Find a material's index in the scene-global material table by pointer.
 * Returns 0 if not found (counts are tiny; linear search is fine). */
static uint32_t global_material_index(const ufbx_scene *scene, const ufbx_material *mat)
{
    for (size_t i = 0; i < scene->materials.count; i++) {
        if (scene->materials.data[i] == mat) return (uint32_t)i;
    }
    return 0;
}

fp_fbx_mesh *fp_fbx_load(const char *path)
{
    fp_fbx_mesh *out = (fp_fbx_mesh *)calloc(1, sizeof(fp_fbx_mesh));
    if (!out) return NULL;

    /* Always give every corner a normal so downstream code never has to special
     * case missing data. Otherwise default options, matching fp_fbx_summarize. */
    ufbx_load_opts opts;
    memset(&opts, 0, sizeof(opts));
    opts.generate_missing_normals = true;

    ufbx_error err;
    ufbx_scene *scene = ufbx_load_file(path, &opts, &err);
    if (!scene) {
        out->ok = 0;
        copy_error(out->error, sizeof(out->error), err.description);
        return out;
    }

    /* First pass: total sizes across all meshes. */
    size_t total_positions = 0, total_corners = 0, total_faces = 0;
    for (size_t i = 0; i < scene->meshes.count; i++) {
        ufbx_mesh *m = scene->meshes.data[i];
        total_positions += m->vertex_position.values.count;
        total_corners   += m->num_indices;
        total_faces     += m->num_faces;
    }

    out->num_positions = total_positions;
    out->num_corners   = total_corners;
    out->num_faces     = total_faces;
    out->num_materials = scene->materials.count;

    /* Allocate. calloc keeps everything zeroed so a partial failure is still
     * safely freeable, and empty meshes leave valid (NULL/0) arrays. */
    int alloc_ok = 1;
    if (total_positions) {
        out->positions = (float *)calloc(total_positions * 3, sizeof(float));
        alloc_ok &= out->positions != NULL;
    }
    if (total_corners) {
        out->corner_position = (uint32_t *)calloc(total_corners, sizeof(uint32_t));
        out->corner_normal   = (float *)calloc(total_corners * 3, sizeof(float));
        out->corner_uv       = (float *)calloc(total_corners * 2, sizeof(float));
        alloc_ok &= out->corner_position && out->corner_normal && out->corner_uv;
    }
    if (total_faces) {
        out->face_first    = (uint32_t *)calloc(total_faces, sizeof(uint32_t));
        out->face_count    = (uint32_t *)calloc(total_faces, sizeof(uint32_t));
        out->face_material = (uint32_t *)calloc(total_faces, sizeof(uint32_t));
        alloc_ok &= out->face_first && out->face_count && out->face_material;
    }
    if (out->num_materials) {
        out->material_names = (char **)calloc(out->num_materials, sizeof(char *));
        alloc_ok &= out->material_names != NULL;
    }
    if (!alloc_ok) {
        ufbx_free_scene(scene);
        out->ok = 0;
        strcpy(out->error, "out of memory while extracting FBX geometry");
        return out; /* arrays remain freeable via fp_fbx_free */
    }

    /* Material names (scene-global table). */
    for (size_t i = 0; i < scene->materials.count; i++) {
        ufbx_string nm = scene->materials.data[i]->name;
        char *buf = (char *)malloc(nm.length + 1);
        if (buf) {
            if (nm.data) memcpy(buf, nm.data, nm.length);
            buf[nm.length] = '\0';
        }
        out->material_names[i] = buf; /* may be NULL on OOM; tolerated */
    }

    /* Second pass: fill. Track running offsets into the merged arrays. */
    size_t pos_base = 0;     /* position offset for the current mesh */
    size_t corner_off = 0;   /* next free corner slot */
    size_t face_off = 0;     /* next free face slot */

    for (size_t i = 0; i < scene->meshes.count; i++) {
        ufbx_mesh *m = scene->meshes.data[i];

        /* Positions: the mesh's unique control points, appended. */
        for (size_t v = 0; v < m->vertex_position.values.count; v++) {
            ufbx_vec3 p = m->vertex_position.values.data[v];
            float *dst = &out->positions[(pos_base + v) * 3];
            dst[0] = (float)p.x;
            dst[1] = (float)p.y;
            dst[2] = (float)p.z;
        }

        bool has_normal = m->vertex_normal.exists;
        bool has_uv = m->vertex_uv.exists;

        for (size_t f = 0; f < m->num_faces; f++) {
            ufbx_face face = m->faces.data[f];

            out->face_first[face_off] = (uint32_t)corner_off;
            out->face_count[face_off] = face.num_indices;

            uint32_t gmat = 0;
            if (m->face_material.count > f) {
                uint32_t local = m->face_material.data[f];
                if (local < m->materials.count) {
                    gmat = global_material_index(scene, m->materials.data[local]);
                }
            }
            out->face_material[face_off] = gmat;
            face_off++;

            for (uint32_t k = 0; k < face.num_indices; k++) {
                uint32_t idx = face.index_begin + k; /* mesh corner index */

                out->corner_position[corner_off] =
                    (uint32_t)(pos_base + m->vertex_position.indices.data[idx]);

                if (has_normal) {
                    ufbx_vec3 n = ufbx_get_vertex_vec3(&m->vertex_normal, idx);
                    float *dn = &out->corner_normal[corner_off * 3];
                    dn[0] = (float)n.x; dn[1] = (float)n.y; dn[2] = (float)n.z;
                }
                if (has_uv) {
                    ufbx_vec2 uv = ufbx_get_vertex_vec2(&m->vertex_uv, idx);
                    float *du = &out->corner_uv[corner_off * 2];
                    du[0] = (float)uv.x; du[1] = (float)uv.y;
                }
                corner_off++;
            }
        }

        pos_base += m->vertex_position.values.count;
    }

    out->ok = 1;
    ufbx_free_scene(scene);
    return out;
}

void fp_fbx_free(fp_fbx_mesh *m)
{
    if (!m) return;
    free(m->positions);
    free(m->corner_position);
    free(m->corner_normal);
    free(m->corner_uv);
    free(m->face_first);
    free(m->face_count);
    free(m->face_material);
    if (m->material_names) {
        for (size_t i = 0; i < m->num_materials; i++) free(m->material_names[i]);
        free(m->material_names);
    }
    free(m);
}
