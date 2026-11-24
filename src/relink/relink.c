/*
 * relink: rename one DT_NEEDED entry of an ELF64 shared library in place (same length or shorter).
 *
 * The OnePlus camera HAL blobs that YAAP ships (SAT/EIS/HIS nodes, camera.oemlayer, ...) were built
 * against OnePlus's libui; YAAP loads them with AOSP's libui.so, whose GraphicBuffer layout differs
 * -> heap corruption in the camera provider. DerpFest relinks them to its libui-stock.so (patchelf
 * --replace-needed). The module ships that library as libus.so (same length as libui.so) and this tool
 * renames the NEEDED string of the ROM's own copies at boot, so a ROM update gets matching relinks.
 *
 *   relink <in> <out> <old> <new>
 * exit 0: <out> written; only the bytes of the NEEDED string differ
 * exit 2: <in> has no DT_NEEDED <old>, nothing written
 * exit 1: anything else (not ELF64 AArch64, string shared with another reference, I/O ...), nothing written
 *
 * Refuses when anything else in the dynamic string table (another dynamic tag, a symbol name, a
 * version record) uses any byte of that string, so the rename can't change another name.
 */
#include <elf.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static unsigned char *d;
static size_t n;

static int fail(const char *m) { fprintf(stderr, "relink: %s\n", m); return 1; }

/* file offset of [vaddr, vaddr+len) through the PT_LOAD segments, or -1 */
static long v2o(const Elf64_Ehdr *eh, uint64_t va, uint64_t len) {
    const Elf64_Phdr *ph = (const Elf64_Phdr *)(d + eh->e_phoff);
    for (int i = 0; i < eh->e_phnum; i++)
        if (ph[i].p_type == PT_LOAD && va >= ph[i].p_vaddr && va + len <= ph[i].p_vaddr + ph[i].p_filesz)
            return (long)(ph[i].p_offset + (va - ph[i].p_vaddr));
    return -1;
}

int main(int argc, char **argv) {
    if (argc != 5) { fprintf(stderr, "usage: %s <in> <out> <old> <new>\n", argv[0]); return 1; }
    const char *oldn = argv[3], *newn = argv[4];
    size_t ol = strlen(oldn), nl = strlen(newn);
    if (!ol || !nl || nl > ol) return fail("new name must not be longer than the old one");

    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) { perror("relink: open in"); return 1; }
    struct stat st;
    if (fstat(fd, &st) || st.st_size < (off_t)sizeof(Elf64_Ehdr) || st.st_size > (256 << 20)) return fail("bad input size");
    n = (size_t)st.st_size;
    d = malloc(n);
    if (!d || read(fd, d, n) != (ssize_t)n) return fail("read failed");
    close(fd);

    const Elf64_Ehdr *eh = (const Elf64_Ehdr *)d;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) || eh->e_ident[EI_CLASS] != ELFCLASS64 ||
        eh->e_ident[EI_DATA] != ELFDATA2LSB || eh->e_machine != EM_AARCH64 || eh->e_type != ET_DYN)
        return fail("not an AArch64 ELF64 shared library");
    if (eh->e_phoff == 0 || eh->e_phoff + (uint64_t)eh->e_phnum * sizeof(Elf64_Phdr) > n) return fail("bad program headers");

    /* dynamic section */
    const Elf64_Phdr *ph = (const Elf64_Phdr *)(d + eh->e_phoff);
    const Elf64_Dyn *dyn = NULL;
    size_t ndyn = 0;
    for (int i = 0; i < eh->e_phnum; i++)
        if (ph[i].p_type == PT_DYNAMIC) {
            if (ph[i].p_offset + ph[i].p_filesz > n) return fail("bad PT_DYNAMIC");
            dyn = (const Elf64_Dyn *)(d + ph[i].p_offset);
            ndyn = ph[i].p_filesz / sizeof(Elf64_Dyn);
        }
    if (!dyn) return fail("no PT_DYNAMIC");
    uint64_t strva = 0, strsz = 0, verneed = 0, verneednum = 0;
    for (size_t i = 0; i < ndyn && dyn[i].d_tag != DT_NULL; i++) {
        if (dyn[i].d_tag == DT_STRTAB) strva = dyn[i].d_un.d_ptr;
        else if (dyn[i].d_tag == DT_STRSZ) strsz = dyn[i].d_un.d_val;
        else if (dyn[i].d_tag == DT_VERNEED) verneed = dyn[i].d_un.d_ptr;
        else if (dyn[i].d_tag == DT_VERNEEDNUM) verneednum = dyn[i].d_un.d_val;
    }
    long stro = strva ? v2o(eh, strva, strsz) : -1;
    if (stro < 0 || !strsz) return fail("dynamic string table not found");
    const char *str = (const char *)d + stro;
    if (str[strsz - 1] != 0) return fail("dynamic string table not NUL-terminated");

    /* every reference into the string table: {offset, is our NEEDED} */
    size_t cap = 1024, nref = 0;
    struct ref { uint64_t off; int target; } *refs = malloc(cap * sizeof(*refs));
#define ADD(o, t) do { if (nref == cap) { cap *= 2; refs = realloc(refs, cap * sizeof(*refs)); if (!refs) return fail("oom"); } \
                       refs[nref].off = (o); refs[nref].target = (t); nref++; } while (0)
    long target = -1;
    int ntarget = 0;
    for (size_t i = 0; i < ndyn && dyn[i].d_tag != DT_NULL; i++) {
        int64_t t = dyn[i].d_tag;
        if (t == DT_NEEDED || t == DT_SONAME || t == DT_RPATH || t == DT_RUNPATH) {
            uint64_t o = dyn[i].d_un.d_val;
            if (o >= strsz) return fail("string offset out of range");
            int is = t == DT_NEEDED && strcmp(str + o, oldn) == 0;
            if (is) { ntarget++; target = (long)o; }
            ADD(o, is);
        }
    }
    if (ntarget == 0) { fprintf(stderr, "relink: no DT_NEEDED %s\n", oldn); return 2; }
    if (ntarget > 1) return fail("several DT_NEEDED entries with that name");

    /* version needs: file and version names */
    if (verneed && verneednum) {
        long vo = v2o(eh, verneed, sizeof(Elf64_Verneed));
        for (uint64_t k = 0; k < verneednum; k++) {
            if (vo < 0 || (size_t)vo + sizeof(Elf64_Verneed) > n) return fail("bad verneed");
            const Elf64_Verneed *vn = (const Elf64_Verneed *)(d + vo);
            ADD(vn->vn_file, 0);
            long ao = vo + vn->vn_aux;
            for (int a = 0; a < vn->vn_cnt; a++) {
                if (ao < 0 || (size_t)ao + sizeof(Elf64_Vernaux) > n) return fail("bad vernaux");
                const Elf64_Vernaux *va = (const Elf64_Vernaux *)(d + ao);
                ADD(va->vna_name, 0);
                if (!va->vna_next) break;
                ao += va->vna_next;
            }
            if (!vn->vn_next) break;
            vo += vn->vn_next;
        }
    }
    /* symbol names (.dynsym and any version-definition section, via the section headers) */
    if (eh->e_shoff == 0 || eh->e_shnum == 0 || eh->e_shoff + (uint64_t)eh->e_shnum * sizeof(Elf64_Shdr) > n)
        return fail("no section headers (can't check the symbol names)");
    const Elf64_Shdr *sh = (const Elf64_Shdr *)(d + eh->e_shoff);
    int dynsym = 0;
    for (int i = 0; i < eh->e_shnum; i++) {
        if (sh[i].sh_type == SHT_DYNSYM) {
            if (sh[i].sh_link >= eh->e_shnum || sh[sh[i].sh_link].sh_offset != (uint64_t)stro) return fail(".dynsym uses another string table");
            if (sh[i].sh_offset + sh[i].sh_size > n || sh[i].sh_entsize != sizeof(Elf64_Sym)) return fail("bad .dynsym");
            const Elf64_Sym *sy = (const Elf64_Sym *)(d + sh[i].sh_offset);
            for (size_t k = 0; k < sh[i].sh_size / sizeof(Elf64_Sym); k++) ADD(sy[k].st_name, 0);
            dynsym = 1;
        } else if (sh[i].sh_type == SHT_GNU_verdef) {
            if (sh[i].sh_offset + sh[i].sh_size > n) return fail("bad verdef");
            long vo = (long)sh[i].sh_offset;
            for (uint64_t k = 0; k < sh[i].sh_info; k++) {
                if ((size_t)vo + sizeof(Elf64_Verdef) > n) return fail("bad verdef");
                const Elf64_Verdef *vd = (const Elf64_Verdef *)(d + vo);
                long ao = vo + vd->vd_aux;
                for (int a = 0; a < vd->vd_cnt; a++) {
                    if ((size_t)ao + sizeof(Elf64_Verdaux) > n) return fail("bad verdaux");
                    const Elf64_Verdaux *va = (const Elf64_Verdaux *)(d + ao);
                    ADD(va->vda_name, 0);
                    if (!va->vda_next) break;
                    ao += va->vda_next;
                }
                if (!vd->vd_next) break;
                vo += vd->vd_next;
            }
        }
    }
    if (!dynsym) return fail("no .dynsym section");

    /* the NEEDED string must start at a string boundary and no other reference may touch its bytes */
    uint64_t lo = (uint64_t)target, hi = lo + ol;   /* [lo, hi] incl. the NUL */
    if (lo > 0 && str[lo - 1] != 0) return fail("NEEDED string is the tail of another string");
    for (size_t i = 0; i < nref; i++) {
        if (refs[i].target) continue;
        uint64_t a = refs[i].off;
        if (a >= strsz) continue;   /* st_name 0 / foreign: outside the table */
        uint64_t b = a + strlen(str + a);
        if (a <= hi && b >= lo) {
            fprintf(stderr, "relink: another reference (offset %llu, \"%s\") shares the NEEDED string\n",
                    (unsigned long long)a, str + a);
            return 1;
        }
    }

    unsigned char *o = malloc(n);
    if (!o) return fail("oom");
    memcpy(o, d, n);
    memset(o + stro + lo, 0, ol);
    memcpy(o + stro + lo, newn, nl);
    size_t diff = 0;
    for (size_t i = 0; i < n; i++)
        if (o[i] != d[i]) {
            if (i < (size_t)stro + lo || i >= (size_t)stro + hi) return fail("internal: change outside the string");
            diff++;
        }
    if (!diff) return fail("internal: nothing changed");

    char tmp[4096];
    snprintf(tmp, sizeof(tmp), "%s.tmp", argv[2]);
    int wfd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (wfd < 0) { perror("relink: open out"); return 1; }
    if (write(wfd, o, n) != (ssize_t)n || fsync(wfd) || close(wfd)) { unlink(tmp); return fail("write failed"); }
    if (rename(tmp, argv[2])) { unlink(tmp); return fail("rename failed"); }
    printf("relinked %s: NEEDED %s -> %s (%zu bytes changed)\n", argv[1], oldn, newn, diff);
    return 0;
}
