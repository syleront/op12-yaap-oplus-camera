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

// ---- Offline-reprocess crop fix (YAAP's own HAL) ------------------------------------------------
// APS sends ANDROID_SCALER_CROP_REGION for its HAL offline sessions (Y2Y/B2Y/MFNR/B2YHDR/R2J) in
// coordinates of the input frame, i.e. the binned 12MP frame for the 50MP quad-bayer sensors.
// The HAL maps the crop into its active array. OnePlus's 16.0.8 sensor drivers report binned
// active arrays (same coordinates, works); YAAP's (16.0.10) report the full quad-bayer arrays
// (8192x6144, 8000x6000, 9248x6944), so the HAL takes a 12MP-space rect as a 50MP one: 2x crop of
// the top-left corner.
// libAlgoProcess's 5 crop setMetadata() call sites go through a stub (src/apscrop) that calls us
// first via the lockPlaneX import: buf = CROP_MAGIC, usage = copy of the new rect, rect = the
// request's camera_metadata. That metadata still holds the HAL's own crop of the original capture
// (active-array coordinates). APS crops are centred, so if the HAL crop's centre is twice the new
// rect's centre, the rect is in half-size coordinates and is doubled. Everything else (OnePlus HAL,
// front camera, full-size 50MP input, no HAL crop present) is left untouched.
#include <dlfcn.h>
#include <string.h>

#define CROP_MAGIC ((uintptr_t)0x43464f50)
#define TAG_SCALER_CROP_REGION 0xD0000u

typedef struct {
    size_t index;
    uint32_t tag;
    uint8_t type;
    size_t count;
    union { const uint8_t *u8; const int32_t *i32; const void *p; } data;
} cm_ro_entry_t;   // camera_metadata_ro_entry_t (system/media/camera)
typedef int (*find_ro_t)(const void *meta, uint32_t tag, cm_ro_entry_t *entry);

static find_ro_t find_ro(void) {
    static find_ro_t f;
    static int done;
    if (!done) {
        f = (find_ro_t)dlsym(RTLD_DEFAULT, "find_camera_metadata_ro_entry");
        if (!f) {
            void *l = dlopen("libcamera_metadata.so", RTLD_NOW | RTLD_NOLOAD);
            if (l) f = (find_ro_t)dlsym(l, "find_camera_metadata_ro_entry");
        }
        if (!f) __android_log_print(ANDROID_LOG_WARN, "apsfix", "crop: find_camera_metadata_ro_entry not found");
        done = 1;
    }
    return f;
}

static int near(int32_t a, int32_t b, int32_t tol) { return a > b ? a - b <= tol : b - a <= tol; }
static int32_t abs32(int32_t a) { return a < 0 ? -a : a; }

static void fix_crop(int32_t *r, const void *meta) {   // r = {left, top, width, height}
    static int logs;
    find_ro_t f = meta ? find_ro() : NULL;
    cm_ro_entry_t e;
    memset(&e, 0, sizeof(e));
    if (!f || f(meta, TAG_SCALER_CROP_REGION, &e) != 0 || e.count != 4 || e.type != 1 /* TYPE_INT32 */) {
        if (logs++ < 50) __android_log_print(ANDROID_LOG_INFO, "apsfix", "crop: (%d,%d,%d,%d) no HAL crop, unchanged",
                                             r[0], r[1], r[2], r[3]);
        return;
    }
    const int32_t *h = e.data.i32;                          // HAL crop, active-array coordinates
    int32_t hx2 = 2 * h[0] + h[2], hy2 = 2 * h[1] + h[3];   // 2 * centres
    int32_t cx2 = 2 * r[0] + r[2], cy2 = 2 * r[1] + r[3];
    // APS moves its crop by the SAT inter-camera image shift (e.g. -52,-52 in a 4096x3072 input when
    // the main camera still serves 3x/6x in low light), so the centres don't coincide exactly. A
    // half-size rect's doubled centre is close to the HAL crop centre while its own centre is about
    // half of it; a rect already in active-array coordinates is the other way round.
    int64_t d1 = (int64_t)abs32(2 * cx2 - hx2) + abs32(2 * cy2 - hy2);   // doubled vs HAL
    int64_t d0 = (int64_t)abs32(cx2 - hx2) + abs32(cy2 - hy2);           // as is vs HAL
    int match = r[2] > 0 && r[3] > 0 && h[2] > 0 && h[3] > 0 && hx2 > 0 && hy2 > 0 &&
                4 * d1 < d0 && near(2 * cx2, hx2, h[2] / 4 + 8) && near(2 * cy2, hy2, h[3] / 4 + 8) &&
                2 * r[2] <= h[2] + h[2] / 16 + 32 && 2 * r[3] <= h[3] + h[3] / 16 + 32;
    if (!match) {
        if (logs++ < 50) __android_log_print(ANDROID_LOG_INFO, "apsfix", "crop: (%d,%d,%d,%d) HAL (%d,%d,%d,%d) unchanged",
                                             r[0], r[1], r[2], r[3], h[0], h[1], h[2], h[3]);
        return;
    }
    int32_t o[4] = {2 * r[0], 2 * r[1], 2 * r[2], 2 * r[3]};
    if (logs++ < 50)
        __android_log_print(ANDROID_LOG_INFO, "apsfix", "crop: (%d,%d,%d,%d) -> (%d,%d,%d,%d), HAL (%d,%d,%d,%d)",
                            r[0], r[1], r[2], r[3], o[0], o[1], o[2], o[3], h[0], h[1], h[2], h[3]);
    memcpy(r, o, sizeof(o));
}

__attribute__((visibility("default")))
int AHardwareBuffer_lockPlaneX(AHardwareBuffer *buf, uint64_t usage, int32_t fence,
                               const ARect *rect, AHardwareBuffer_Planes *out) {
    if ((uintptr_t)buf == CROP_MAGIC) {   // crop stub in libAlgoProcess: usage = int32_t rect[4], rect = metadata
        if (usage) fix_crop((int32_t *)(uintptr_t)usage, rect);
        return 0;
    }
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
