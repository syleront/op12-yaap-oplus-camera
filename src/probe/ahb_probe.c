// Allocate an AHardwareBuffer like OPlus APS does and print what gralloc reports.
#include <android/hardware_buffer.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void probe(uint32_t fmt, uint32_t w, uint32_t h, uint64_t usage) {
    AHardwareBuffer_Desc d = { .width = w, .height = h, .layers = 1, .format = fmt, .usage = usage };
    AHardwareBuffer *b = NULL;
    int r = AHardwareBuffer_allocate(&d, &b);
    printf("fmt=0x%x %ux%u usage=0x%llx alloc=%d\n", fmt, w, h, (unsigned long long)usage, r);
    if (r) return;
    AHardwareBuffer_Desc o; AHardwareBuffer_describe(b, &o);
    printf("  describe: stride=%u\n", o.stride);
    AHardwareBuffer_Planes p;
    r = AHardwareBuffer_lockPlanes(b, AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1, NULL, &p);
    printf("  lockPlanes=%d planeCount=%u\n", r, r ? 0 : p.planeCount);
    for (uint32_t i = 0; !r && i < p.planeCount; i++)
        printf("   plane%u data=%p pixelStride=%u rowStride=%u\n", i, p.planes[i].data, p.planes[i].pixelStride, p.planes[i].rowStride);
    if (!r && p.planeCount >= 2) printf("   uvOffset=%td -> scanline=%td\n", (char*)p.planes[1].data - (char*)p.planes[0].data, ((char*)p.planes[1].data - (char*)p.planes[0].data) / (p.planes[0].rowStride ? p.planes[0].rowStride : 1));
    if (!r) AHardwareBuffer_unlock(b, NULL);
    AHardwareBuffer_release(b);
}
int main(int argc, char **argv) {
    probe(0x7fa30c0a, 4096, 3072, 0x20003);   // QTI P010_VENUS, as APS
    probe(0x36,       4096, 3072, 0x3);       // AOSP YCBCR_P010
    probe(0x23,       4096, 3072, 0x3);       // YUV_420_888
    char l[512]; FILE *m = fopen("/proc/self/maps", "r"); while (m && fgets(l, sizeof l, m)) if (strstr(l, "/vendor/") || strstr(l, "libui.so")) { if (strstr(l, "r-xp")) fputs(l, stdout); } 
    return 0;
}
