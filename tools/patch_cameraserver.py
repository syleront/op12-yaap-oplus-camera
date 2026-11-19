# Patches DerpFest's /system/bin/cameraserver (CameraService is linked statically into it; the
# payload libcameraservice.so is NOT the code that runs) so the OnePlus camera never shares the
# camera HAL with another app (sharing crashes the OnePlus HAL):
#  1. CAF's isPrivilegedClient() (persist.vendor.camera.privapp.list = com.oplus.camera, still
#     needed by the framework and the CameraDeviceClient ctor) cleared the eviction lists in
#     handleEvictionsLocked/finishConnectLocked, so other apps were never evicted -> bl -> mov w0,#0.
#  2. The HAL accepts e.g. front (cost 33) + camera 2 (cost 66) and then crashes, so a stub
#     (src/evictfix/cave.s, placed in the zero padding after .plt) sets the privileged client's
#     resource cost to 100 before wouldEvictLocked(); the R+X PT_LOAD is extended to cover it.
# usage: python3 patch_cameraserver.py <in> <out>
import hashlib, struct, sys
IN_MD5 = '5547ec78e5db7deed92612e81739508c'
OUT_MD5 = 'ca45c8570630cb84800c7775200620d3'
IS_PRIV, WOULD_EVICT, CAVE = 0xf5ca4, 0xf620c, 0x37eee0
CAVE_CODE = bytes.fromhex('fd7bbda9fd030091e00701a9e81300f9e04f40f96cdbf597a0000036e10f40f9290040f98a0c80522a2100b9e00741a9e81340f9e2031f2afd7bc3a8bcdcf517')
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected cameraserver (not the tested DerpFest build)'
def bl_target(off):
    ins = struct.unpack_from('<I', d, off)[0]
    assert ins >> 26 == 0x25, hex(off)
    imm = ins & 0x3ffffff
    return off + (imm - 0x4000000 if imm & 0x2000000 else imm) * 4
for off in (0xf14fc, 0xf44d8):          # handleEvictionsLocked, finishConnectLocked
    assert bl_target(off) == IS_PRIV
    struct.pack_into('<I', d, off, 0x52800000)        # mov w0, #0
assert len(CAVE_CODE) <= 0x40 and d[CAVE:CAVE + 0x40] == bytes(0x40)
d[CAVE:CAVE + len(CAVE_CODE)] = CAVE_CODE
assert bl_target(0xf14ec) == WOULD_EVICT
struct.pack_into('<I', d, 0xf14ec, 0x94000000 | (((CAVE - 0xf14ec) >> 2) & 0x3ffffff))
phoff = struct.unpack_from('<Q', d, 0x20)[0]; phentsize, phnum = struct.unpack_from('<HH', d, 0x36)
for i in range(phnum):
    o = phoff + i * phentsize
    p_type, p_flags, p_off, _, _, p_fsz, p_msz, _ = struct.unpack_from('<IIQQQQQQ', d, o)
    if p_type == 1 and p_flags == 5:
        assert p_off + p_fsz == CAVE and p_fsz == p_msz
        struct.pack_into('<QQ', d, o + 32, CAVE + 0x40 - p_off, CAVE + 0x40 - p_off)
assert hashlib.md5(d).hexdigest() == OUT_MD5, 'patched result differs from the tested one'
open(sys.argv[2], 'wb').write(d)
print('cameraserver patched', OUT_MD5)
