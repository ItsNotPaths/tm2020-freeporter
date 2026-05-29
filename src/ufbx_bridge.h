/* Thin C shim over ufbx. The Nim side binds only these flat entry points, not
 * ufbx's full struct API — that keeps the Nim binding tiny and the FBX-specific
 * complexity contained on the C side. New flat entry points get added here as
 * the importer pipeline needs real geometry. */
#ifndef FP_UFBX_BRIDGE_H
#define FP_UFBX_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int    ok;          /* 1 on success, 0 on load failure */
    size_t meshes;
    size_t materials;
    size_t vertices;    /* summed across all meshes */
    size_t faces;
    size_t triangles;
    char   error[512];  /* NUL-terminated; populated when ok == 0 */
} fp_fbx_summary;

/* Load `path` and report counts. Frees the scene before returning. */
fp_fbx_summary fp_fbx_summarize(const char *path);

/* Full geometry extraction, flattened into plain arrays the Nim side can copy
 * out without touching ufbx's headers. The whole scene is merged into one
 * vertex/face soup with a single global material table:
 *
 *   - `positions` are the FBX control points (unique vertex positions), 3 floats
 *     each. Faces index into them via `corner_position`.
 *   - a "corner" is one vertex of one face (a face-vertex). `num_corners` is the
 *     sum of every face's vertex count. `corner_position[c]` indexes `positions`;
 *     `corner_normal`/`corner_uv` carry the per-corner normal (3f) and UV set 0
 *     (2f). Faces are kept as-is (NOT triangulated) so quads/ngons survive.
 *   - `face_first[f]` is the first corner of face f, `face_count[f]` its corner
 *     count (>= 3 for valid faces), `face_material[f]` an index into
 *     `material_names` (0 when the mesh has no material binding).
 *
 * Positions/corners from multiple meshes are concatenated; position indices and
 * material indices are rebased into the merged/global space. */
typedef struct {
    int        ok;
    char       error[512];

    size_t     num_positions;
    float     *positions;        /* 3 * num_positions */

    size_t     num_corners;
    uint32_t  *corner_position;  /* num_corners: index into positions */
    float     *corner_normal;    /* 3 * num_corners */
    float     *corner_uv;        /* 2 * num_corners (UV set 0; 0,0 if absent) */

    size_t     num_faces;
    uint32_t  *face_first;       /* num_faces */
    uint32_t  *face_count;       /* num_faces */
    uint32_t  *face_material;    /* num_faces: index into material_names */

    size_t     num_materials;
    char     **material_names;   /* num_materials NUL-terminated names */
} fp_fbx_mesh;

/* Load `path` and extract merged geometry. Always returns a heap object (NULL
 * only on allocation failure of the object itself); check `->ok`. Release with
 * fp_fbx_free. */
fp_fbx_mesh *fp_fbx_load(const char *path);
void fp_fbx_free(fp_fbx_mesh *m);

#endif
