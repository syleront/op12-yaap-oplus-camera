// HEIC fix for the OnePlus camera (libAPSClient-cmd-jni.so).
//
// libAlgoProcess.so (OnePlus HAL) passes the HEIF encoder parameters to the JNI library as a
// std::map whose keys end in "_<TYPE>_BASIC_" (e.g. "exifData_bufferPlanesWidth_INT_BASIC_").
// actionSetHeifProcess() in libAPSClient-cmd-jni.so still looks them up by the older names
// without "BASIC_" ("exifData_bufferPlanesWidth_INT_"), finds nothing and encodes a 0x0 image,
// so HEIC photos are saved without the picture. DerpFest has the same pair of libraries.
//
// This library is added to libAPSClient-cmd-jni.so as DT_NEEDED. Its constructor redirects the
// library's PLT slot for std::map<string, vector<string>>::find() to find_compat(), which
// retries a failed "exifData_..._" lookup with "BASIC_" appended. Nothing else changes.
#include <android/log.h>
#include <elf.h>
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define _GNU_SOURCE
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define TAG "heiffix"
#define LOG(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

static const char TARGET_LIB[] = "/libAPSClient-cmd-jni.so";
// std::__ndk1::map<std::string, std::vector<std::string>>::find<std::string>(const std::string&)
static const char FIND_SYM[] =
    "_ZNSt6__ndk16__treeINS_12__value_typeINS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE"
    "NS_6vectorIS7_NS5_IS7_EEEEEENS_19__map_value_compareIS7_SB_NS_4lessIS7_EELb1EEENS5_ISB_EEE4findIS7_"
    "EENS_15__tree_iteratorISB_PNS_11__tree_nodeISB_PvEElEERKT_";

// libc++ (std::__ndk1) std::string, little-endian: long mode if bit 0 of the first byte is set.
struct lstr { size_t cap; size_t size; const char *data; };

static const char *str_data(const void *s, size_t *len) {
    const unsigned char *b = s;
    if (b[0] & 1) { const struct lstr *l = s; *len = l->size; return l->data; }
    *len = b[0] >> 1;
    return (const char *)b + 1;
}

typedef void *(*find_fn)(void *tree, const void *key);
static find_fn real_find;

static void *find_compat(void *tree, const void *key) {
    void *it = real_find(tree, key);
    void *end = (char *)tree + sizeof(void *);  // __tree::__end_node_
    if (it != end) return it;

    size_t n;
    const char *k = str_data(key, &n);
    static const char pre[] = "exifData_";
    if (n < sizeof(pre) || n > 200 || memcmp(k, pre, sizeof(pre) - 1) != 0 || k[n - 1] != '_') return it;
    // Leave the 3A debug blob out: heifProcess() (libHeifEncoderWrapper.so) writes it to the file and
    // then free()s the pointer, which is the c_str() of the map's string, so the camera aborts. When the
    // key is missing the JNI library passes NULL and the encoder skips it.
    if (memmem(k, n, "HeifDebug", 9)) return it;

    // old name -> new name: "..._INT_" -> "..._INT_BASIC_", "..._BYTEARRAY_" -> "..._BYTE_BASIC_ARRAY_"
    static const char oldarr[] = "_BYTEARRAY_", newarr[] = "_BYTE_BASIC_ARRAY_", basic[] = "BASIC_";
    char buf[224];
    size_t m;
    if (n >= sizeof(oldarr) - 1 && memcmp(k + n - (sizeof(oldarr) - 1), oldarr, sizeof(oldarr) - 1) == 0) {
        m = n - (sizeof(oldarr) - 1);
        memcpy(buf, k, m);
        memcpy(buf + m, newarr, sizeof(newarr));
        m += sizeof(newarr) - 1;
    } else if (n >= sizeof(basic) - 1 && memcmp(k + n - (sizeof(basic) - 1), basic, sizeof(basic) - 1) == 0) {
        return it;
    } else {
        memcpy(buf, k, n);
        memcpy(buf + n, basic, sizeof(basic));
        m = n + sizeof(basic) - 1;
    }
    struct lstr alt = { .cap = sizeof(buf) | 1, .size = m, .data = buf };
    void *it2 = real_find(tree, &alt);
#ifdef HEIFFIX_DEBUG
    if (it2 != end) {
        // node: __tree_node_base (3 ptrs + bool, 32 bytes), key string (24), value vector<string> (begin, end, cap)
        const void *const *vec = (const void *const *)((const char *)it2 + 0x38);
        size_t vn = 0;
        const char *v = vec[0] != vec[1] ? str_data(vec[0], &vn) : "";
        char hex[3 * 24 + 1] = "";
        for (size_t i = 0; i < vn && i < 24; i++) snprintf(hex + 3 * i, 4, "%02x ", (unsigned char)v[i]);
        LOG("%.*s -> %s: len %zu [%s] (%zu values)", (int)n, k, buf, vn, hex,
            (size_t)((const char *)vec[1] - (const char *)vec[0]) / 24);
    } else {
        LOG("%.*s: not found as %s either", (int)n, k, buf);
    }
    static int dumped;
    if (!dumped) {  // all keys of the first map seen
        dumped = 1;
        const void *stack[64]; int sp = 0;
        const void *node = *(const void *const *)end;  // root = end_node.__left_
        while (node || sp) {
            while (node && sp < 64) { stack[sp++] = node; node = *(const void *const *)node; }
            node = stack[--sp];
            size_t kn, vn = 0;
            const char *kk = str_data((const char *)node + 0x20, &kn);
            const void *const *vec = (const void *const *)((const char *)node + 0x38);
            if (vec[0] != vec[1]) str_data(vec[0], &vn);
            LOG("map: %.*s (value len %zu)", (int)kn, kk, vn);
            node = ((const void *const *)node)[1];
        }
    }
#endif
    return it2 != end ? it2 : it;
}

static uintptr_t lib_base(void) {
    FILE *f = fopen("/proc/self/maps", "re");
    if (!f) return 0;
    char line[512];
    uintptr_t base = 0;
    while (fgets(line, sizeof(line), f)) {
        unsigned long start, off;
        if (!strstr(line, TARGET_LIB) || sscanf(line, "%lx-%*lx %*s %lx", &start, &off) != 2 || off != 0) continue;
        base = start;
        break;
    }
    fclose(f);
    return base;
}

__attribute__((constructor)) static void heiffix_init(void) {
    uintptr_t base = lib_base();
    if (!base) { LOG("%s not mapped, nothing to do", TARGET_LIB + 1); return; }
    const ElfW(Ehdr) *eh = (const void *)base;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0) { LOG("bad ELF header"); return; }
    const ElfW(Phdr) *ph = (const void *)(base + eh->e_phoff);
    const ElfW(Dyn) *dyn = NULL;
    for (int i = 0; i < eh->e_phnum; i++)
        if (ph[i].p_type == PT_DYNAMIC) dyn = (const void *)(base + ph[i].p_vaddr);
    if (!dyn) { LOG("no PT_DYNAMIC"); return; }

    const ElfW(Sym) *symtab = NULL; const char *strtab = NULL;
    const ElfW(Rela) *jmprel = NULL; size_t pltrelsz = 0;
    for (; dyn->d_tag != DT_NULL; dyn++) {
        switch (dyn->d_tag) {
            case DT_SYMTAB: symtab = (const void *)(base + dyn->d_un.d_ptr); break;
            case DT_STRTAB: strtab = (const void *)(base + dyn->d_un.d_ptr); break;
            case DT_JMPREL: jmprel = (const void *)(base + dyn->d_un.d_ptr); break;
            case DT_PLTRELSZ: pltrelsz = dyn->d_un.d_val; break;
        }
    }
    if (!symtab || !strtab || !jmprel) { LOG("missing dynamic tables"); return; }

    for (size_t i = 0; i < pltrelsz / sizeof(ElfW(Rela)); i++) {
        const ElfW(Rela) *r = &jmprel[i];
        if (ELF64_R_TYPE(r->r_info) != R_AARCH64_JUMP_SLOT) continue;
        if (strcmp(strtab + symtab[ELF64_R_SYM(r->r_info)].st_name, FIND_SYM) != 0) continue;

        void **slot = (void **)(base + r->r_offset);
        long pg = sysconf(_SC_PAGESIZE);
        uintptr_t page = (uintptr_t)slot & ~(uintptr_t)(pg - 1);
        if (mprotect((void *)page, pg, PROT_READ | PROT_WRITE) != 0) { LOG("mprotect failed"); return; }
        real_find = (find_fn)*slot;
        *slot = (void *)find_compat;
        mprotect((void *)page, pg, PROT_READ);  // the GOT is RELRO
        LOG("redirected map::find in %s (slot +0x%lx)", TARGET_LIB + 1, (unsigned long)r->r_offset);
        return;
    }
    LOG("map::find PLT slot not found");
}
