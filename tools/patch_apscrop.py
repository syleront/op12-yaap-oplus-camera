# Offline-reprocess crop fix for libAlgoProcess.so, applied on top of patch_algoprocess.py's output.
#
# APS sets ANDROID_SCALER_CROP_REGION for its HAL offline sessions in input-frame coordinates (the
# binned 12MP frame). YAAP's 16.0.10 sensor drivers report the full quad-bayer active arrays, so the
# HAL crops the top-left quarter. The 5 crop setMetadata() calls (IPE Y2Y, B2Y, MFNR, B2YHDR, R2J;
# not the "restore HAL crop" one at 0x6967c0) are redirected to src/apscrop/cropstub.s, which lets
# libapsfix rescale a copy of the rect (no-op on the OnePlus HAL, whose arrays are binned).
# The stub lives in the zero padding after the RX PT_LOAD (0x70d3c0..0x70e000, file offset == vaddr);
# that segment's p_filesz/p_memsz are extended to cover it.
# usage: python3 patch_apscrop.py <in> <out>
import hashlib, struct, sys
IN_MD5 = 'f217e98b44b2baab38407d5df71c6fac'
d = bytearray(open(sys.argv[1], 'rb').read())
assert hashlib.md5(d).hexdigest() == IN_MD5, 'unexpected libAlgoProcess.so (run patch_algoprocess.py first)'
STUB_AT, SET_METADATA = 0x70d3c0, 0x6fdc88
STUB = bytes.fromhex(   # build cropstub.bin (src/apscrop/cropstub.s linked at 0x70d3c0)
    'fd7bbca9fd030091e00701a9e31300f9482440a9e82703a9e1c30091e30300aa'
    '00ea89d2c068a8f28ecbff97e00741a9e31340f9e2c3009124c2ff97fd7bc4a8'
    'c0035fd6')
def bl(src, dst):
    return struct.pack('<I', 0x94000000 | (((dst - src) >> 2) & 0x3ffffff))
# RX PT_LOAD = phdr[2]
ph = 64 + 2 * 56
typ, flags, off, va, pa, fsz, msz, al = struct.unpack_from('<IIQQQQQQ', d, ph)
assert (typ, flags, off, va, fsz, msz) == (1, 5, 0x14c000, 0x14c000, 0x5c13c0, 0x5c13c0), 'RX phdr'
assert d[STUB_AT:0x70e000] == bytes(0x70e000 - STUB_AT), 'padding not empty'
d[STUB_AT:STUB_AT + len(STUB)] = STUB
end = STUB_AT + len(STUB) - 0x14c000
struct.pack_into('<QQ', d, ph + 32, end, end)
for site in (0x695994, 0x699ae4, 0x69d2c4, 0x69e708, 0x6a0000):
    assert d[site:site + 4] == bl(site, SET_METADATA), hex(site)
    d[site:site + 4] = bl(site, STUB_AT)
open(sys.argv[2], 'wb').write(d)
print('libAlgoProcess.so crop-patched', hashlib.md5(d).hexdigest())
