// Ask the gralloc mapper (via libui GraphicBufferMapper::getPlaneLayouts) for the plane
// layout of a buffer, the way OPlus APS does, reading platform C++ structs raw.
#include <android/hardware_buffer.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct { void *b, *e, *c; } vec;                       // libc++ std::vector
typedef struct { char name[24]; int64_t value; int64_t offBits, sizeBits; } comp;  // PlaneLayoutComponent (48B)
typedef struct { vec comps; int64_t off, incBits, stride, w, h, total, hs, vs; } plane;   // PlaneLayout (88B)
typedef void *(*getinst_t)(void);
typedef int (*getpl_t)(void *self, const void *handle, vec *out);
extern const void *AHardwareBuffer_getNativeHandle(const AHardwareBuffer *);
int main(void) {
    void *ui = dlopen("libui.so", RTLD_NOW);
    getinst_t gi = (getinst_t)dlsym(ui, "_ZN7android9SingletonINS_19GraphicBufferMapperEE11getInstanceEv");
    getpl_t gp = (getpl_t)dlsym(ui, "_ZN7android19GraphicBufferMapper15getPlaneLayoutsEPK13native_handlePNSt3__16vectorIN4aidl7android8hardware8graphics6common11PlaneLayoutENS4_9allocatorISB_EEEE");
    if (!gi || !gp) { printf("dlsym failed %p %p\n", gi, gp); return 1; }
    uint32_t fmts[] = { 0x7fa30c0a, 0x36 };
    for (int f = 0; f < 2; f++) {
        AHardwareBuffer_Desc d = { .width = 4096, .height = 3072, .layers = 1, .format = fmts[f], .usage = f ? 3 : 0x20003 };
        AHardwareBuffer *b = NULL;
        if (AHardwareBuffer_allocate(&d, &b)) { printf("alloc fail\n"); continue; }
        vec out = {0};
        int r = gp(gi(), AHardwareBuffer_getNativeHandle(b), &out);
        int n = out.b ? (int)(((char *)out.e - (char *)out.b) / sizeof(plane)) : 0;
        printf("fmt=0x%x getPlaneLayouts=%d planes=%d\n", fmts[f], r, n);
        for (int i = 0; i < n; i++) {
            plane *p = (plane *)out.b + i;
            int nc = (int)(((char *)p->comps.e - (char *)p->comps.b) / sizeof(comp));
            printf("  plane%d off=%lld incBits=%lld stride=%lld w=%lld h=%lld total=%lld sub=%lldx%lld comps:", i,
                   (long long)p->off, (long long)p->incBits, (long long)p->stride, (long long)p->w, (long long)p->h, (long long)p->total, (long long)p->hs, (long long)p->vs);
            for (int c = 0; c < nc; c++) { comp *k = (comp *)p->comps.b + c; printf(" [type=%lld off=%lld size=%lld]", (long long)k->value, (long long)k->offBits, (long long)k->sizeBits); }
            printf("\n");
        }
        AHardwareBuffer_release(b);
    }
    char l[512]; FILE *m = fopen("/proc/self/maps", "r");
    while (m && fgets(l, sizeof l, m)) if (strstr(l, "libgralloccore") && strstr(l, "r-xp")) fputs(l, stdout);
    return 0;
}
