# Patches DerpFest's /odm/lib64/libAlgoProcess.so (OnePlus APS).
#
# 1. YAAP's libnativewindow: DerpFest's framework returns Y + CbCr planes from
#    AHardwareBuffer_lockPlanes() for the QTI P010_VENUS format (0x7fa30c0a); stock AOSP returns one
#    plane and APS crashes on capture.
#    - the import AHardwareBuffer_lockPlanes is renamed to AHardwareBuffer_lockPlaneX
#    - NEEDED libextendfile.so is repointed to libapsfix.so (src/apsfix, which provides
#      AHardwareBuffer_lockPlaneX and NEEDs libextendfile.so itself)
# 2. HEIC EXIF: ApsCallbackCapture::preProcess() passes the HEIC EXIF block to the camera's JNI
#    library as std::string(""); s.append(exif) -- append(const char*) stops at the first NUL, right
#    after "Exif", and the encoder then reads 1348 bytes from a 4-byte string. The 11 instructions at
#    0x328a00 are replaced with s = {}; s.append(exif, exifSize) (exif pointer and size are at
#    +0xbc0 / +0xbc8 of the same struct; the size is what the code sends as ExifSize next).
#    Same length; file offset == vaddr in this segment. See also src/heiffix.
# usage: python3 patch_algoprocess.py <in> <out>
import hashlib, sys
IN_MD5 = 'b706aa115dff69d3468c1ee61b24cd37'
OUT_MD5 = 'f217e98b44b2baab38407d5df71c6fac'
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected libAlgoProcess.so (not the tested DerpFest build)'
def put(off, old, new):
    assert d[off:off + len(old)] == old, hex(off)
    assert len(new) == len(old)
    d[off:off + len(new)] = new
put(241368, b'AHardwareBuffer_lockPlanes\0', b'AHardwareBuffer_lockPlaneX\0')
put(534952, b'libextendfile.so\0', b'libapsfix.so\0\0\0\0\0')
put(0x328a00, bytes.fromhex(
    '61ecff90'   # adrp x1, 0xb4000
    '211c2391'   # add  x1, x1, #0x8c7          ; ""
    'e0433791'   # add  x0, sp, #0xdd0
    'ffef06f9'   # str  xzr, [sp, #0xdd8]
    'ffeb06f9'   # str  xzr, [sp, #0xdd0]
    'fff306f9'   # str  xzr, [sp, #0xde0]
    '79cdf897'   # bl   std::string(const char*)
    '680240f9'   # ldr  x8, [x19]
    'e0433791'   # add  x0, sp, #0xdd0
    '01e145f9'   # ldr  x1, [x8, #0xbc0]        ; exif
    '0a4f0f94'), # bl   append(const char*)@plt
    bytes.fromhex(
    'e0433791'   # add  x0, sp, #0xdd0
    '1f7c00a9'   # stp  xzr, xzr, [x0]
    '1f0800f9'   # str  xzr, [x0, #0x10]       ; empty string
    '680240f9'   # ldr  x8, [x19]
    '01e145f9'   # ldr  x1, [x8, #0xbc0]        ; exif
    '02c94bb9'   # ldr  w2, [x8, #0xbc8]        ; exif size
    '00510f94'   # bl   append(const char*, size_t)@plt (0x6fce18)
    '1f2003d5' '1f2003d5' '1f2003d5' '1f2003d5'))  # nop x4
assert hashlib.md5(d).hexdigest() == OUT_MD5, 'patched result differs from the tested one'
open(sys.argv[2], 'wb').write(d)
print('libAlgoProcess.so patched', OUT_MD5)
