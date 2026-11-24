# OnePlus-camera-only characteristics trimming for YAAP's HAL (src/shim/charfilter.cpp) hooked into
# the module's cameraserver, on top of patch_cs_physmeta.py's output.
# CameraService::getCameraCharacteristics (0xc15ac) has two `bl atrace_get_enabled_tags`
# (ATRACE_CALL begin/end checks); both go to src/csfix/charstub.s placed at 0x37ef40 (zero padding
# after the earlier caves), which calls into libcsext_shim.so and then tail-calls atrace:
#   0xc15f8 (entry, x21 = cameraInfo, x24 = &clientAttribution) -> charenter 0x37ef40
#   0xc1c5c (common exit, x19 = Status*)                           -> charexit  0x37ef7c
# The R+X PT_LOAD is extended to cover the stub.
# usage: python3 patch_cs_chars.py <in> <out>
import hashlib, struct, sys
IN_MD5 = '193055470551581a75b8d551978f6e47'
ATRACE_PLT, CAVE = 0x37bbd0, 0x37ef40
SITES = {0xc15f8: 0x37ef40, 0xc1c5c: 0x37ef7c}
STUB = bytes.fromhex(   # src/csfix/charstub.s linked at 0x37ef40 (see tools/build_native.sh)
    'fd7bbfa9fd03009160030010410080529cfcff97000100b461030030a1fcff97'
    'a00000b4e90300aae00315aae10318aa20013fd6fd7bc1a816f3ff17fd7bbfa9'
    'fd03009180010010410080528dfcff97e00000b40102007092fcff97800000b4'
    'e90300aae00313aa20013fd6fd7bc1a808f3ff176c696263736578745f736869'
    '6d2e736f006f7063616d5f63686172735f656e746572006f7063616d5f636861'
    '72735f65786974001f2003d51f2003d5')
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected cameraserver (run patch_cs_physmeta.py first)'
def bl(src, dst):
    return struct.pack('<I', 0x94000000 | (((dst - src) >> 2) & 0x3ffffff))
# prologue keeps the arguments in callee-saved registers: x19 = sret, x21 = x6, x24 = x4
for off, ins in ((0xc15d0, 'f30308aa'), (0xc15d4, 'f50306aa'), (0xc15e0, 'f80304aa')):
    assert d[off:off + 4] == bytes.fromhex(ins), hex(off)
for site in SITES:
    assert d[site:site + 4] == bl(site, ATRACE_PLT), 'bl atrace_get_enabled_tags expected at ' + hex(site)
assert d[CAVE:CAVE + 0x100] == bytes(0x100), 'cave not empty'
d[CAVE:CAVE + len(STUB)] = STUB
for site, dst in SITES.items():
    d[site:site + 4] = bl(site, dst)
end = CAVE + len(STUB)
phoff = struct.unpack_from('<Q', d, 0x20)[0]; phentsize, phnum = struct.unpack_from('<HH', d, 0x36)
for i in range(phnum):
    o = phoff + i * phentsize
    p_type, p_flags, p_off, _, _, p_fsz, p_msz, _ = struct.unpack_from('<IIQQQQQQ', d, o)
    if p_type == 1 and p_flags == 5:
        assert p_off + p_fsz == CAVE and p_fsz == p_msz, hex(p_off + p_fsz)
        struct.pack_into('<QQ', d, o + 32, end - p_off, end - p_off)
open(sys.argv[2], 'wb').write(d)
print('cameraserver chars-patched', hashlib.md5(d).hexdigest())
