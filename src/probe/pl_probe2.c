#include <android/hardware_buffer.h>
typedef struct { int version, numFds, numInts; int data[]; } native_handle_t;
extern const native_handle_t *AHardwareBuffer_getNativeHandle(const AHardwareBuffer *);
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
typedef struct { void *b, *e, *c; } vec;
typedef struct { vec comps; int64_t off, incBits, stride, w, h, total, hs, vs; } plane;
typedef void *(*getinst_t)(void);
typedef int (*getpl_t)(void *, const void *, vec *);
int main(void) {
    void *ui = dlopen("libui.so", RTLD_NOW);
    getinst_t gi = (getinst_t)dlsym(ui, "_ZN7android9SingletonINS_19GraphicBufferMapperEE11getInstanceEv");
    getpl_t gp = (getpl_t)dlsym(ui, "_ZN7android19GraphicBufferMapper15getPlaneLayoutsEPK13native_handlePNSt3__16vectorIN4aidl7android8hardware8graphics6common11PlaneLayoutENS4_9allocatorISB_EEEE");
    int sz[][2] = {{4096,3072},{4000,3000},{1920,1080},{4080,3060},{8192,6144},{3264,2448},{1000,750}};
    for (int s = 0; s < 7; s++) {
        AHardwareBuffer_Desc d = { .width = sz[s][0], .height = sz[s][1], .layers = 1, .format = 0x7fa30c0a, .usage = 0x20003 };
        AHardwareBuffer *b = NULL;
        if (AHardwareBuffer_allocate(&d, &b)) { printf("alloc fail\n"); continue; }
        AHardwareBuffer_Desc o; AHardwareBuffer_describe(b, &o);
        const native_handle_t *h = AHardwareBuffer_getNativeHandle(b);
        vec out = {0}; gp(gi(), h, &out);
        plane *p = (plane *)out.b;
        printf("%dx%d desc.stride=%u | p0 stride=%lld total=%lld | p1 off=%lld stride=%lld | uvoff/stride=%lld | h: fds=%d ints=%d:", sz[s][0], sz[s][1], o.stride,
               (long long)p[0].stride, (long long)p[0].total, (long long)p[1].off, (long long)p[1].stride, (long long)(p[1].off / p[0].stride), h->numFds, h->numInts);
        for (int i = 0; i < h->numInts && i < 16; i++) printf(" %d", h->data[h->numFds + i]);
        printf("\n");
        AHardwareBuffer_Planes pl; void *a = NULL;
        int r = AHardwareBuffer_lockPlanes(b, 3, -1, NULL, &pl);
        printf("   lockPlanes r=%d n=%u\n", r, pl.planeCount);
        if (!r) AHardwareBuffer_unlock(b, NULL);
        AHardwareBuffer_release(b);
    }
    return 0;
}
