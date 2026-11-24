# Null guard for physical-camera result metadata in the module's cameraserver (on top of
# patch_cameraserver.py's output).
# camera3::processCaptureResult() does CameraMetadata::append(result->physcam_metadata[i]) for every
# physical camera of a result. YAAP's own HAL (16.0.10) sends an empty physical metadata in the
# OnePlus portrait (bokeh) capture; the AIDL glue turns that into NULL and cameraserver segfaults in
# get_camera_metadata_entry_count(NULL). The append call is redirected to a 3-instruction stub in
# the zero padding after the previous cave (0x37ef20) that skips NULL (the physical result then
# carries an empty CameraMetadata, which the rest of the code handles). The R+X PT_LOAD is
# extended to cover it. No-op for the OnePlus HAL, which never sends empty physical metadata.
# usage: python3 patch_cs_physmeta.py <in> <out>
import hashlib, struct, sys
IN_MD5 = 'ca45c8570630cb84800c7775200620d3'
SITE, APPEND_PLT, CAVE = 0x25fcc0, 0x37c690, 0x37ef20
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected cameraserver (run patch_cameraserver.py first)'
def branch(op, src, dst):
    return struct.pack('<I', op | (((dst - src) >> 2) & 0x3ffffff))
assert d[SITE - 4:SITE] == bytes.fromhex('017976f8'), 'ldr x1, [x8, x22, lsl #3] expected'
assert d[SITE:SITE + 4] == branch(0x94000000, SITE, APPEND_PLT), 'bl append expected'
cave = (
        struct.pack('<I', 0xb4000000 | (2 << 5) | 1) +     # cbz x1, +8
        branch(0x14000000, CAVE + 4, APPEND_PLT) +          # b   CameraMetadata::append@plt
        bytes.fromhex('c0035fd6'))                          # ret
assert d[CAVE:CAVE + 0x20] == bytes(0x20), 'cave not empty'
d[CAVE:CAVE + len(cave)] = cave
d[SITE:SITE + 4] = branch(0x94000000, SITE, CAVE)
phoff = struct.unpack_from('<Q', d, 0x20)[0]; phentsize, phnum = struct.unpack_from('<HH', d, 0x36)
for i in range(phnum):
    o = phoff + i * phentsize
    p_type, p_flags, p_off, _, _, p_fsz, p_msz, _ = struct.unpack_from('<IIQQQQQQ', d, o)
    if p_type == 1 and p_flags == 5:
        assert p_off + p_fsz == CAVE and p_fsz == p_msz
        struct.pack_into('<QQ', d, o + 32, CAVE + 0x20 - p_off, CAVE + 0x20 - p_off)
open(sys.argv[2], 'wb').write(d)
print('cameraserver physmeta-patched', hashlib.md5(d).hexdigest())
