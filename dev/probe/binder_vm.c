#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    void *h = dlopen("libbinder_ndk.so", RTLD_NOW);
    void *(*chk)(const char *) = h ? (void *(*)(const char *))dlsym(h, "AServiceManager_checkService") : NULL;
    printf("checkService(activity)=%p\n", chk ? chk("activity") : NULL);
    char l[512]; unsigned long a, b; FILE *m = fopen("/proc/self/maps", "r");
    while (m && fgets(l, sizeof l, m))
        if (strstr(l, "binder") && !strstr(l, ".so") && sscanf(l, "%lx-%lx", &a, &b) == 2)
            printf("%lu KB  %s", (b - a) / 1024, l);
    return 0;
}
