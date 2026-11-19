# Patches DerpFest's /odm/lib64/libAlgoProcess.so (OnePlus APS) for YAAP's libnativewindow.
# DerpFest's framework returns Y + CbCr planes from AHardwareBuffer_lockPlanes() for the QTI
# P010_VENUS format (0x7fa30c0a); stock AOSP returns one plane and APS crashes on capture.
#  - the import AHardwareBuffer_lockPlanes is renamed to AHardwareBuffer_lockPlaneX
#  - NEEDED libextendfile.so is repointed to libapsfix.so (src/apsfix, which provides
#    AHardwareBuffer_lockPlaneX and NEEDs libextendfile.so itself)
# usage: python3 patch_algoprocess.py <in> <out>
import hashlib, sys
IN_MD5 = 'b706aa115dff69d3468c1ee61b24cd37'
OUT_MD5 = '68fc7841b75b62d0369c7db90a9832e8'
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected libAlgoProcess.so (not the tested DerpFest build)'
def put(off, old, new):
    assert d[off:off + len(old)] == old, hex(off)
    assert len(new) == len(old)
    d[off:off + len(new)] = new
put(241368, b'AHardwareBuffer_lockPlanes\0', b'AHardwareBuffer_lockPlaneX\0')
put(534952, b'libextendfile.so\0', b'libapsfix.so\0\0\0\0\0')
assert hashlib.md5(d).hexdigest() == OUT_MD5, 'patched result differs from the tested one'
open(sys.argv[2], 'wb').write(d)
print('libAlgoProcess.so patched', OUT_MD5)
