// OnePlus camera view of YAAP's camera characteristics (YAAP HAL mode).
//
// YAAP's 16.0.10 sensor drivers advertise full quad-bayer sizes (main 8192x6144, UW 8000x6000 RAW
// + 4096x3072 YUV, tele 9248x6944 ...) and leave com.oplus.bokeh.zoom.picture.size empty. The
// 16.0.8 OnePlus camera app picks the largest size everywhere: portrait asks the HAL for 50MP and
// stalls, master mode on the UW pairs 8000x6000 RAW with 4096x3072 output, etc. With the OnePlus
// 16.0.8 sensor drivers the app only ever saw the binned sizes.
// For the OnePlus camera only (clientAttribution packageName "com.oplus.camera"), this trims
// each quad-bayer camera's size lists back to the binned sizes and restores the two OnePlus tags
// the 16.0.8 drivers had. The active arrays stay as the HAL reports them (all coordinates the app
// sends must stay in HAL space; libAlgoProcess's offline crop is handled by libapsfix). Other apps
// and the HAL itself are not affected.
//
// Hooks: tools/patch_cs_chars.py makes CameraService::getCameraCharacteristics() (cameraserver)
// call opcam_chars_enter(cameraInfo, clientAttribution) on entry and opcam_chars_exit(status) on its
// way out (src/csfix/charstub.s), looked up with dlopen("libcsext_shim.so") + dlsym (this library
// is already loaded as libcsextimpl.so's dependency).
#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define TAG "opcamfix"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

namespace {

struct Entry {   // camera_metadata_entry_t
    size_t index;
    uint32_t tag;
    uint8_t type;
    size_t count;
    union { uint8_t *u8; int32_t *i32; int64_t *i64; void *p; } data;
};
typedef Entry (*find_t)(void *meta, uint32_t tag);
typedef int (*upd32_t)(void *meta, uint32_t tag, const int32_t *data, size_t count);
typedef int (*upd64_t)(void *meta, uint32_t tag, const int64_t *data, size_t count);
typedef void *(*ipc_self_t)();
typedef int (*ipc_uid_t)(const void *ipc);

find_t g_find;
upd32_t g_upd32;
upd64_t g_upd64;
ipc_self_t g_ipc_self;
ipc_uid_t g_ipc_uid;
int g_ready;   // 0 = not tried, 1 = ok, -1 = failed

const uint32_t ACTIVE_ARRAY = 0xF0000, PHYSICAL_IDS = 0x1A0000, OPAQUE_RAW_SIZE = 0xE001E;
const uint32_t CONFIGS32[] = {0xD000A /* scaler stream configs */, 0x1C0000 /* heic */, 0x210000 /* jpeg_r */};
const uint32_t DURATIONS64[] = {0xD000B, 0xD000C, 0x1C0001, 0x1C0002, 0x210001, 0x210002};
const uint32_t MULTI_RES = 0xD0013;          // physicalCameraMultiResolutionStreamConfigurations
const uint32_t OPLUS_RAW_SIZE = 0x80EB0019;   // com.oplus.custom.raw.size (w,h pairs)
const uint32_t OPLUS_QCFA_REMOSAIC = 0x80EB0017; // com.oplus.QCFARemosaicType (16.0.8: 1, YAAP: -1)
const uint32_t OPLUS_BOKEH_SIZE = 0x80EC0026; // com.oplus.bokeh.zoom.picture.size (16.0.8 value below)
const int32_t BOKEH_SIZES[] = {4096, 3072, 4096, 3072, 4096, 3072, 4096, 3072, 4096, 3072, 4608, 3456};
const int32_t LOGICAL_MAX_W = 4624, LOGICAL_MAX_H = 3472;   // largest binned size of the physical cameras (tele)

bool init() {
    if (g_ready) return g_ready > 0;
    g_ready = -1;
    // libcamera_client / libbinder are cameraserver's own DT_NEEDED: global group
    g_find = (find_t)dlsym(RTLD_DEFAULT, "_ZN7android14CameraMetadata4findEj");
    g_upd32 = (upd32_t)dlsym(RTLD_DEFAULT, "_ZN7android14CameraMetadata6updateEjPKim");
    g_upd64 = (upd64_t)dlsym(RTLD_DEFAULT, "_ZN7android14CameraMetadata6updateEjPKlm");
    g_ipc_self = (ipc_self_t)dlsym(RTLD_DEFAULT, "_ZN7android14IPCThreadState4selfEv");
    g_ipc_uid = (ipc_uid_t)dlsym(RTLD_DEFAULT, "_ZNK7android14IPCThreadState13getCallingUidEv");
    if (!g_find || !g_upd32 || !g_upd64 || !g_ipc_self || !g_ipc_uid) { LOGW("missing symbols"); return false; }
    g_ready = 1;
    return true;
}

// AttributionSourceState (AIDL parcelable, libc++): vtable, int pid @8, int uid @0xc, int deviceId @0x10
// (cameraserver itself reads deviceId from +0x10), std::optional<std::string> packageName @0x18
// (engaged flag @0x30). The camera app's CameraManager fills packageName from its Context.
bool attribution_package(const void *attr, char *out, size_t outSize) {
    const uint8_t *a = (const uint8_t *)attr;
    out[0] = 0;
    if (!a || !(a[0x30] & 1)) return false;
    const uint8_t *s = a + 0x18;
    const char *p;
    size_t n;
    if (s[0] & 1) {   // long string: {cap | 1, size, data}
        memcpy(&n, s + 8, sizeof(n));
        memcpy(&p, s + 16, sizeof(p));
        if (!p || n > 256) return false;
    } else {          // short string: {size << 1, chars[23]}
        n = s[0] >> 1;
        p = (const char *)s + 1;
        if (n > 22) return false;
    }
    if (n >= outSize) n = outSize - 1;
    memcpy(out, p, n);
    out[n] = 0;
    return true;
}

bool is_oplus_camera(const char *pkg) { return strcmp(pkg, "com.oplus.camera") == 0; }

inline bool fits(int32_t w, int32_t h, int32_t mw, int32_t mh) { return w <= mw && h <= mh; }

// int32 (format, w, h, isInput) quads: drop oversize entries
int filter32(void *meta, uint32_t tag, int32_t mw, int32_t mh) {
    Entry e = g_find(meta, tag);
    if (e.count < 4 || e.type != 1 /* INT32 */) return 0;
    size_t n = e.count / 4, k = 0;
    int32_t buf[e.count];
    for (size_t i = 0; i < n; i++) {
        const int32_t *q = e.data.i32 + 4 * i;
        if (!fits(q[1], q[2], mw, mh)) continue;
        memcpy(buf + 4 * k++, q, 4 * sizeof(int32_t));
    }
    if (k == n) return 0;
    g_upd32(meta, tag, buf, 4 * k);
    return (int)(n - k);
}

// int64 (format, w, h, duration) quads: drop oversize entries
int filter64(void *meta, uint32_t tag, int32_t mw, int32_t mh) {
    Entry e = g_find(meta, tag);
    if (e.count < 4 || e.type != 3 /* INT64 */) return 0;
    size_t n = e.count / 4, k = 0;
    int64_t buf[e.count];
    for (size_t i = 0; i < n; i++) {
        const int64_t *q = e.data.i64 + 4 * i;
        if (!fits((int32_t)q[1], (int32_t)q[2], mw, mh)) continue;
        memcpy(buf + 4 * k++, q, 4 * sizeof(int64_t));
    }
    if (k == n) return 0;
    g_upd64(meta, tag, buf, 4 * k);
    return (int)(n - k);
}

// int32 tuples of `stride` starting with (w, h): drop oversize entries
int filter_wh(void *meta, uint32_t tag, size_t stride, int32_t mw, int32_t mh) {
    Entry e = g_find(meta, tag);
    if (e.count < stride || e.type != 1) return 0;
    size_t n = e.count / stride, k = 0;
    int32_t buf[e.count];
    for (size_t i = 0; i < n; i++) {
        const int32_t *q = e.data.i32 + stride * i;
        if (!fits(q[0], q[1], mw, mh)) continue;
        memcpy(buf + stride * k++, q, stride * sizeof(int32_t));
    }
    if (k == n) return 0;
    g_upd32(meta, tag, buf, stride * k);
    return (int)(n - k);
}

// multi-resolution configs: oversize sizes become the binned size (16.0.8 listed those)
int fix_multires(void *meta, int32_t mw, int32_t mh, int32_t bw, int32_t bh) {
    Entry e = g_find(meta, MULTI_RES);
    if (e.count < 4 || e.type != 1) return 0;
    size_t n = e.count / 4, k = 0;
    int changed = 0;
    int32_t buf[e.count];
    for (size_t i = 0; i < n; i++) {
        int32_t q[4];
        memcpy(q, e.data.i32 + 4 * i, sizeof(q));
        if (!fits(q[1], q[2], mw, mh)) { q[1] = bw; q[2] = bh; changed++; }
        bool dup = false;
        for (size_t j = 0; j < k && !dup; j++) dup = !memcmp(buf + 4 * j, q, sizeof(q));
        if (!dup) memcpy(buf + 4 * k++, q, sizeof(q));
    }
    if (!changed) return 0;
    g_upd32(meta, MULTI_RES, buf, 4 * k);
    return changed;
}

void trim(void *meta, int pid) {
    Entry a = g_find(meta, ACTIVE_ARRAY);
    if (a.count < 4 || a.type != 1) return;
    int32_t aw = a.data.i32[2], ah = a.data.i32[3];
    if (aw < 6000) return;   // not a quad-bayer camera reported at full size (front, or OnePlus HAL)
    bool logical = g_find(meta, PHYSICAL_IDS).count > 0;
    int32_t mw = logical ? LOGICAL_MAX_W : aw / 2, mh = logical ? LOGICAL_MAX_H : ah / 2;
    int removed = 0;
    for (uint32_t t : CONFIGS32) removed += filter32(meta, t, mw, mh);
    for (uint32_t t : DURATIONS64) removed += filter64(meta, t, mw, mh);
    removed += filter_wh(meta, OPAQUE_RAW_SIZE, 3, mw, mh);
    removed += filter_wh(meta, OPLUS_RAW_SIZE, 2, mw, mh);
    int multi = fix_multires(meta, mw, mh, aw / 2, ah / 2);
    int32_t one = 1;
    Entry q = g_find(meta, OPLUS_QCFA_REMOSAIC);
    if (q.count == 1 && q.type == 1 && q.data.i32[0] != 1) g_upd32(meta, OPLUS_QCFA_REMOSAIC, &one, 1);
    bool bokeh = g_find(meta, OPLUS_BOKEH_SIZE).count == 0;
    if (bokeh) g_upd32(meta, OPLUS_BOKEH_SIZE, BOKEH_SIZES, sizeof(BOKEH_SIZES) / sizeof(int32_t));
    static int logs;
    if (logs++ < 40)
        LOGI("pid %d: %dx%d%s limit %dx%d: removed %d entries, multires %d, bokeh %s", pid, aw, ah,
             logical ? " (logical)" : "", mw, mh, removed, multi, bokeh ? "added" : "kept");
}

__thread void *t_meta;   // cameraInfo of the OnePlus camera's call in progress on this binder thread
__thread int t_pid;

}  // namespace

// Hook at the start of CameraService::getCameraCharacteristics (src/csfix/charstub.s).
extern "C" __attribute__((visibility("default"))) void opcam_chars_enter(void *meta, const void *attr) {
    t_meta = nullptr;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    bool ok = init();
    pthread_mutex_unlock(&lock);
    if (!ok || !meta || !attr) return;
    char pkg[64];
    bool have = attribution_package(attr, pkg, sizeof(pkg));
    const uint8_t *a = (const uint8_t *)attr;
    int32_t pid, uid;
    memcpy(&pid, a + 8, 4);
    memcpy(&uid, a + 0xc, 4);
    bool oplus = have && is_oplus_camera(pkg);
    static int calls;
    if (calls++ < 40 || oplus) {
        static int ologs;
        if (!oplus || ologs++ < 12)
            LOGI("getCameraCharacteristics: pid %d uid %d calling uid %d package '%s'%s", pid, uid,
                 g_ipc_uid(g_ipc_self()), have ? pkg : "?", oplus ? " -> OnePlus view" : "");
    }
    if (oplus) { t_meta = meta; t_pid = pid; }
}

// Hook at its common exit; status = the binder::Status being returned (mException @0, 0 = OK).
extern "C" __attribute__((visibility("default"))) void opcam_chars_exit(const void *status) {
    void *meta = t_meta;
    t_meta = nullptr;
    if (!meta || !status) return;
    int32_t ex;
    memcpy(&ex, status, 4);
    if (ex == 0) trim(meta, t_pid);
}
