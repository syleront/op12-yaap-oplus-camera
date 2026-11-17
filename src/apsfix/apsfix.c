// libapsfix.so - loaded only by OPlus APS (libAlgoProcess.so, whose import of
// AHardwareBuffer_lockPlanes is renamed to AHardwareBuffer_lockPlaneX and whose
// NEEDED libextendfile.so is repointed here; we re-NEED libextendfile.so).
//
// DerpFest's framework libnativewindow treats QTI HAL_PIXEL_FORMAT_YCbCr_420_P010_VENUS
// (0x7fa30c0a) as YUV and returns Y + interleaved CbCr planes. Stock AOSP (YAAP) returns a
// single plane, APS then derives scanline from a NULL UV pointer and crashes on capture.
// Here we add the missing planes for that one format; everything else passes through.
#include <android/hardware_buffer.h>
#include <android/log.h>
#include <stdint.h>

#define FMT_P010_VENUS 0x7fa30c0a
#define QTI_HANDLE_MAGIC 1735226221 /* private_handle_t.magic as seen on SM8650 gralloc */

typedef struct { int version, numFds, numInts; int data[]; } nh_t;
extern const nh_t *AHardwareBuffer_getNativeHandle(const AHardwareBuffer *);

__attribute__((visibility("default")))
int AHardwareBuffer_lockPlaneX(AHardwareBuffer *buf, uint64_t usage, int32_t fence,
                               const ARect *rect, AHardwareBuffer_Planes *out) {
    int r = AHardwareBuffer_lockPlanes(buf, usage, fence, rect, out);
    if (r != 0 || !buf || !out || out->planeCount != 1) return r;
    AHardwareBuffer_Desc d;
    AHardwareBuffer_describe(buf, &d);
    if (d.format != FMT_P010_VENUS) return r;
    if (rect && (rect->left || rect->top)) return r;   // APS locks whole buffers; don't guess offsets

    // Aligned scanline: QTI private_handle_t ints = {magic, flags, aligned_w, aligned_h, ...};
    // gralloc's PlaneLayout puts CbCr at rowStride * aligned_h. Fallback: ALIGN(h, 32).
    uint32_t sl = (d.height + 31u) & ~31u;
    const nh_t *h = AHardwareBuffer_getNativeHandle(buf);
    if (h && h->numInts > 3 && h->data[h->numFds] == QTI_HANDLE_MAGIC) {
        int ah = h->data[h->numFds + 3];
        if (ah >= (int)d.height && ah <= (int)d.height + 64) sl = (uint32_t)ah;
    }
    uint8_t *y = (uint8_t *)out->planes[0].data;
    uint32_t rs = out->planes[0].rowStride;
    out->planeCount = 3;
    out->planes[0].pixelStride = 2;
    out->planes[1].data = y + (uint64_t)rs * sl;       // Cb (10 bits in a 16-bit LE word)
    out->planes[1].pixelStride = 4;
    out->planes[1].rowStride = rs;
    out->planes[2].data = y + (uint64_t)rs * sl + 2;   // Cr
    out->planes[2].pixelStride = 4;
    out->planes[2].rowStride = rs;
    static int logged;
    if (!logged) {
        logged = 1;
        __android_log_print(ANDROID_LOG_INFO, "apsfix", "P010_VENUS %ux%u rowStride=%u scanline=%u -> 3 planes",
                            d.width, d.height, rs, sl);
    }
    return r;
}
