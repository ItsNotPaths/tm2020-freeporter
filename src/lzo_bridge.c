#include "lzo_bridge.h"
#include "minilzo.h"

/* minilzo requires a one-time lzo_init(). Guard it so repeated calls are cheap
 * and thread-unsafety isn't a concern (this tool is single-threaded). */
static int lzo_ready = 0;

static int ensure_init(void)
{
    if (lzo_ready) return 0;
    if (lzo_init() != LZO_E_OK) return -1;
    lzo_ready = 1;
    return 0;
}

int fp_lzo_decompress(const uint8_t *src, size_t src_len,
                      uint8_t *dst, size_t dst_cap, size_t *out_len)
{
    if (ensure_init() != 0) return -1;

    lzo_uint produced = (lzo_uint)dst_cap;
    int r = lzo1x_decompress((const lzo_bytep)src, (lzo_uint)src_len,
                             (lzo_bytep)dst, &produced, NULL);
    if (r != LZO_E_OK) return r;
    if (out_len) *out_len = (size_t)produced;
    return 0;
}

size_t fp_lzo_compress_bound(size_t src_len)
{
    /* Oberhumer's documented worst case for LZO1X. */
    return src_len + src_len / 16 + 64 + 3;
}

int fp_lzo_compress(const uint8_t *src, size_t src_len,
                    uint8_t *dst, size_t *out_len)
{
    if (ensure_init() != 0) return -1;

    /* LZO1X-1 work memory; sized by the minilzo macro. */
    static unsigned char wrkmem[LZO1X_1_MEM_COMPRESS];

    lzo_uint produced = 0;
    int r = lzo1x_1_compress((const lzo_bytep)src, (lzo_uint)src_len,
                             (lzo_bytep)dst, &produced, wrkmem);
    if (r != LZO_E_OK) return r;
    if (out_len) *out_len = (size_t)produced;
    return 0;
}
