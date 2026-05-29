/* Thin C shim over minilzo (Oberhumer LZO1X). GBX bodies are LZO1X-compressed;
 * the Nim side binds only these two flat entry points and lets minilzo's headers
 * stay on the C side. Both return 0 on success, non-zero on error. */
#ifndef FP_LZO_BRIDGE_H
#define FP_LZO_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

/* Decompress `src_len` bytes at `src` into `dst` (capacity `dst_cap`, which for
 * GBX is the exact uncompressed size from the body header). On success writes
 * the produced length to `*out_len` and returns 0. */
int fp_lzo_decompress(const uint8_t *src, size_t src_len,
                      uint8_t *dst, size_t dst_cap, size_t *out_len);

/* Compress `src_len` bytes at `src` into `dst`. `dst` must have capacity at
 * least fp_lzo_compress_bound(src_len). Writes the produced length to `*out_len`
 * and returns 0 on success. Uses LZO1X-1 (fast). */
int fp_lzo_compress(const uint8_t *src, size_t src_len,
                    uint8_t *dst, size_t *out_len);

/* Worst-case compressed size for `src_len` input bytes. */
size_t fp_lzo_compress_bound(size_t src_len);

#endif
