/*
 * binderpatch: raise libbinder's binder VM size from 1 MB to 4 MB (as on OOS/DerpFest).
 *
 * ProcessState maps/unmaps BINDER_VM_SIZE = 1MB - 2*page. Clang emits, at both sites:
 *     mov  w8, #0x100000          08 02 a0 52
 *     subs x1, x8, x0, lsl #1     01 05 00 eb
 * We change the immediate to #0x400000 (08 08 a0 52).
 *
 *   binderpatch <in> <out>
 * exit 0: patched copy written to <out>      (exactly 2 stock sites found)
 * exit 2: input already uses 4 MB, nothing written
 * exit 1: anything else (pattern count unexpected, I/O error), nothing written
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const unsigned char STOCK[8]   = {0x08, 0x02, 0xa0, 0x52, 0x01, 0x05, 0x00, 0xeb};
static const unsigned char PATCHED[8] = {0x08, 0x08, 0xa0, 0x52, 0x01, 0x05, 0x00, 0xeb};

static size_t find_all(const unsigned char *d, size_t n, const unsigned char *pat, size_t *offs, size_t max) {
    size_t c = 0;
    /* instructions are 4-byte aligned */
    for (size_t i = 0; i + 8 <= n; i += 4)
        if (memcmp(d + i, pat, 8) == 0) { if (c < max) offs[c] = i; c++; }
    return c;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s <in> <out>\n", argv[0]); return 1; }
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) { perror("open in"); return 1; }
    struct stat st;
    if (fstat(fd, &st) || st.st_size < 4096 || st.st_size > 64 << 20) { fprintf(stderr, "bad input size\n"); return 1; }
    size_t n = (size_t)st.st_size;
    unsigned char *d = malloc(n);
    if (!d) return 1;
    size_t got = 0;
    while (got < n) { ssize_t r = read(fd, d + got, n - got); if (r <= 0) { perror("read"); return 1; } got += (size_t)r; }
    close(fd);
    if (memcmp(d, "\x7f" "ELF", 4) != 0 || d[4] != 2 /* 64-bit */) { fprintf(stderr, "not an ELF64 file\n"); return 1; }

    size_t offs[8];
    size_t ns = find_all(d, n, STOCK, offs, 8);
    size_t np = find_all(d, n, PATCHED, NULL, 0);
    if (ns == 0 && np == 2) { printf("already 4MB\n"); return 2; }
    if (ns != 2 || np != 0) { fprintf(stderr, "unexpected pattern count: stock=%zu patched=%zu\n", ns, np); return 1; }
    for (size_t i = 0; i < ns; i++) { d[offs[i] + 1] = 0x08; printf("patched 0x%zx\n", offs[i]); }

    char tmp[4096];
    snprintf(tmp, sizeof tmp, "%s.tmp", argv[2]);
    int o = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (o < 0) { perror("open out"); return 1; }
    size_t w = 0;
    while (w < n) { ssize_t r = write(o, d + w, n - w); if (r <= 0) { perror("write"); close(o); unlink(tmp); return 1; } w += (size_t)r; }
    if (fsync(o) || close(o)) { unlink(tmp); return 1; }
    if (rename(tmp, argv[2])) { perror("rename"); unlink(tmp); return 1; }
    return 0;
}
