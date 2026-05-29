/* Thin C shim over ufbx. The Nim side binds only these flat entry points, not
 * ufbx's full struct API — that keeps the Nim binding tiny and the FBX-specific
 * complexity contained on the C side. New flat entry points get added here as
 * the importer pipeline needs real geometry. */
#ifndef FP_UFBX_BRIDGE_H
#define FP_UFBX_BRIDGE_H

#include <stddef.h>

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

#endif
