# libAlgoInterface.so (DerpFest, odm/lib64; runs in the camera app): textEnhanceUninit() null check.
#
# textEnhanceRegister() allocates the text-enhance engine (a global pointer) and frees it, setting the
# pointer to NULL, if loading its library fails; textEnhanceUnregister() frees it too. Unregister first calls
# textEnhanceUninit(), which reads engine->handle without checking the engine pointer, so a second
# unregister (or one after a failed register) crashes the camera app when the camera closes:
#     SIGSEGV fault addr 0x48 in textEnhanceUninit()+388 <- textEnhanceUnregister <-
#     AlgoUnitStatusMgr::executeAllAlgoUninitLocked <- APSCaptureManager::apsRoutine
# (seen on YAAP when pausing the camera). Unregister itself already handles a NULL engine.
#
# Patch: the load of the engine pointer jumps to a 5-instruction trampoline placed in the zero padding
# right after the R E segment (the segment's file/mem size grows by 20 bytes, still inside its last page):
#     ldr x8, [x19, #0x438]        ; engine (original instruction)
#     cbz x8, 1f
#     ldr x0, [x8, #0x48]          ; engine->handle (original instruction)
#     b   <back: cbz x0, ...>
#  1: b   <the function's existing "handle == NULL" path: return -1>
# usage: python3 patch_algointerface.py <in.so> <out.so>
import hashlib, struct, sys
IN_MD5 = '4bdb78a5e2b831cb4e27dbe2a0dd2516'
LOAD_PC = 0x29fae84      # ldr x8, [x19, #0x438]   (textEnhanceUninit+0x180)
NULL_RET = 0x29faf94     # mov w0, #-1 ; b epilogue
CAVE = 0x2aca1a0         # end of the R E segment (= end of .plt); file offset == vaddr here

d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected libAlgoInterface.so'
def u32(o): return struct.unpack_from('<I', d, o)[0]
def put(o, w): struct.pack_into('<I', d, o, w)
def b(frm, to):
    off = (to - frm) // 4; assert -(1 << 25) <= off < (1 << 25); return 0x14000000 | (off & 0x3ffffff)
def cbz_x(rt, frm, to):
    off = (to - frm) // 4; assert -(1 << 18) <= off < (1 << 18); return 0xb4000000 | ((off & 0x7ffff) << 5) | rt

LDR_G, LDR_H, CBZ_H = u32(LOAD_PC), u32(LOAD_PC + 4), u32(LOAD_PC + 8)
assert LDR_G == 0xf9421e68, hex(LDR_G)                     # ldr x8, [x19, #0x438]
assert LDR_H == 0xf9402500, hex(LDR_H)                     # ldr x0, [x8, #0x48]
assert CBZ_H == cbz_x(0, LOAD_PC + 8, NULL_RET), hex(CBZ_H) # cbz x0, NULL_RET
assert u32(NULL_RET) == 0x12800000                         # mov w0, #-1

# program headers: the R E LOAD ends exactly at CAVE and the next LOAD starts on the next page
phoff, = struct.unpack_from('<Q', d, 0x20); phnum, = struct.unpack_from('<H', d, 0x38)
rx = None
for i in range(phnum):
    o = phoff + 56 * i
    typ, flg, off, va, pa, fsz, msz, al = struct.unpack_from('<IIQQQQQQ', d, o)
    if typ == 1 and flg == 5: assert rx is None; rx = (o, off, va, fsz, msz)
    if typ == 1 and va > CAVE: assert va >= (CAVE + 0xfff) & ~0xfff
o, off, va, fsz, msz = rx
assert off == va and va + fsz == CAVE and fsz == msz, (hex(off), hex(va), hex(fsz))
N = 5
assert d[CAVE:CAVE + 4 * N] == bytes(4 * N) and CAVE + 4 * N <= (CAVE + 0xfff) & ~0xfff

cave = [LDR_G,
        cbz_x(8, CAVE + 4, CAVE + 16),
        LDR_H,
        b(CAVE + 12, LOAD_PC + 8),
        b(CAVE + 16, NULL_RET)]
for k, w in enumerate(cave): put(CAVE + 4 * k, w)
put(LOAD_PC, b(LOAD_PC, CAVE))
struct.pack_into('<QQ', d, o + 32, fsz + 4 * N, msz + 4 * N)

open(sys.argv[2], 'wb').write(d)
print('libAlgoInterface.so patched', hashlib.md5(d).hexdigest())
