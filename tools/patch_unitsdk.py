# Hi-Res (high_pixel_mode) on YAAP's HAL: HighPixelMode.getSurfaceSize() in the camera unit SDK jar.
#
# For the raw_output / raw16_output streams the app asks the HAL for the largest RAW16 size of the
# camera's stream map, which src/shim/charfilter.cpp trims to the binned size (4096x3072) for the
# OnePlus camera, while the capture streams stay at 8192x6144. The HAL then fails the 50 MP snapshot
# (camxbpsnode "Mismatch input resolution (8192, 6144) and output DS4 resolution (4096, 3072)"), the
# buffers are lost and the camera service drops the device. With the raw outputs at the picture size
# (8192x6144, a size the HAL supports) the 1x Hi-Res photo works.
#
# Only for rear_main: on the 0.6x/3x lenses the app expects a binned capture that it upscales itself,
# and full-size raw outputs give a striped image there (they keep the old behaviour).
#
# The switch case raw_output/raw16_output starts with
#     if (isSupportRawMaxFullSize() && (isSupportMasterModeV21() || HYBRIDRAW)) -> A else -> B
# (12 code units up to the second branch). All three are global config values, false on the OnePlus 12
# (only B was ever taken), so the same 12 code units become
#     if ("rear_main".equals(cameraType)) -> A else -> B
# and in A (unused until now) new Pair(appSize, rawMaxSize) becomes new Pair(appSize, appSize).
# The dex keeps its layout; checksum and signature are recomputed and the jar is rebuilt (stored,
# classes.dex 4-byte aligned like the original).
# usage: python3 patch_unitsdk.py <in.jar> <out.jar>
import hashlib, struct, sys, zipfile, zlib
IN_MD5 = '791111178b3103b1087b0baa7580de6e'

src = open(sys.argv[1], 'rb').read()
assert hashlib.md5(src).hexdigest() == IN_MD5, 'unexpected com.oplus.camera.unit.sdk.jar'
z = zipfile.ZipFile(sys.argv[1])
assert z.namelist() == ['classes.dex'], z.namelist()
d = bytearray(z.read('classes.dex'))

def u32(o): return struct.unpack_from('<I', d, o)[0]
def uleb(o):
    r = s = 0
    while True:
        b = d[o]; o += 1; r |= (b & 0x7f) << s; s += 7
        if b < 0x80: return r, o
str_n, str_off = u32(0x38), u32(0x3c)
type_off, proto_off = u32(0x44), u32(0x4c)
meth_n, meth_off = u32(0x58), u32(0x5c)
cls_n, cls_off = u32(0x60), u32(0x64)
def string(i):
    _, o = uleb(u32(str_off + 4 * i))
    return bytes(d[o:d.index(0, o)]).decode('latin-1')   # MUTF-8; only ASCII names are looked up
strings = [string(i) for i in range(str_n)]
sidx = {s: i for i, s in enumerate(strings)}
def tname(t): return strings[u32(type_off + 4 * t)]
def method(cls, name, shorty):
    found = [i for i in range(meth_n)
             if tname(struct.unpack_from('<H', d, meth_off + 8 * i)[0]) == cls
             and strings[u32(meth_off + 8 * i + 4)] == name
             and strings[u32(proto_off + 12 * struct.unpack_from('<H', d, meth_off + 8 * i + 2)[0])] == shorty]
    assert len(found) == 1, (cls, name, found)
    return found[0]
HELPER = 'Lcom/oplus/ocs/camera/producer/info/CameraConfigHelper;'
M_RAWFULL = method(HELPER, 'isSupportRawMaxFullSize', 'Z')
M_MASTER21 = method(HELPER, 'isSupportMasterModeV21', 'Z')
M_EQUALS = method('Ljava/lang/String;', 'equals', 'ZL')
M_PAIR = method('Landroid/util/Pair;', '<init>', 'VLL')
M_SURF = method('Lcom/oplus/ocs/camera/producer/mode/HighPixelMode;', 'getSurfaceSize', 'LLLLLI')
S_MAIN = sidx['rear_main']
assert S_MAIN < 0x10000

# code item of HighPixelMode.getSurfaceSize (class_data: direct then virtual methods, deltas)
code = None
for c in range(cls_n):
    if tname(u32(cls_off + 32 * c)) != 'Lcom/oplus/ocs/camera/producer/mode/HighPixelMode;': continue
    o = u32(cls_off + 32 * c + 24)
    nsf, o = uleb(o); nif, o = uleb(o); ndm, o = uleb(o); nvm, o = uleb(o)
    for _ in range(2 * (nsf + nif)): _, o = uleb(o)
    for n in (ndm, nvm):
        m = 0
        for _ in range(n):
            dm, o = uleb(o); _, o = uleb(o); co, o = uleb(o)
            m += dm
            if m == M_SURF: code = co
assert code, 'getSurfaceSize code not found'
regs, ins = struct.unpack_from('<HH', d, code)
insns_n = u32(code + 12)
base = code + 16
P0 = regs - ins   # p0 = this
P4 = P0 + 4       # cameraType (String str3)
assert P4 < 16

def cu(i): return struct.unpack_from('<H', d, base + 2 * i)[0]
# the case: invoke-static {} RAWFULL; move-result v2; if-eqz v2 B; invoke-static {} MASTER21; move-result v2; if-nez v2 A
hits = []
for i in range(insns_n - 12):
    if (cu(i), cu(i + 1), cu(i + 2), cu(i + 3), cu(i + 4)) == (0x0071, M_RAWFULL, 0, 0x020a, 0x0238) and \
       (cu(i + 6), cu(i + 7), cu(i + 8), cu(i + 9), cu(i + 10)) == (0x0071, M_MASTER21, 0, 0x020a, 0x0239):
        hits.append(i)
assert len(hits) == 1, hits
i = hits[0]
to_b = i + 4 + struct.unpack_from('<h', d, base + 2 * (i + 5))[0]
to_a = i + 10 + struct.unpack_from('<h', d, base + 2 * (i + 11))[0]
# A: ... invoke-direct {p2, p1, p0}, Pair.<init> (first one after A)
pair = [j for j in range(to_a, to_a + 40) if cu(j) == 0x3070 and cu(j + 1) == M_PAIR]
assert pair, 'Pair.<init> not found in branch A'
j = pair[0]
regs3 = cu(j + 2)
c_, d_, e_ = regs3 & 15, (regs3 >> 4) & 15, (regs3 >> 8) & 15
assert (c_, d_, e_) == (P0 + 2, P0 + 1, P0) and regs3 >> 12 == 0, hex(regs3)

new = [0x021a, S_MAIN,                       # const-string v2, "rear_main"
       0x206e, M_EQUALS, (P4 << 4) | 2,      # invoke-virtual {v2, p4}, String.equals
       0x020a]                               # move-result v2
new += [0x0239, (to_a - (i + 6)) & 0xffff]   # if-nez v2, A
new += [((to_b - (i + 8)) & 0xff) << 8 | 0x28]   # goto B
assert -128 <= to_b - (i + 8) < 128
new += [0x0000] * (12 - len(new))            # nop
for k, w in enumerate(new): struct.pack_into('<H', d, base + 2 * (i + k), w)
struct.pack_into('<H', d, base + 2 * (j + 2), (d_ << 8) | (d_ << 4) | c_)   # {p2, p1, p1}

d[12:32] = hashlib.sha1(d[32:]).digest()
struct.pack_into('<I', d, 8, zlib.adler32(bytes(d[12:])) & 0xffffffff)
dex_md5 = hashlib.md5(d).hexdigest()

# jar: one stored entry, data 4-byte aligned (local header 30 + 11-byte name + 3-byte extra = 44)
zi = zipfile.ZipInfo('classes.dex', (1980, 1, 1, 0, 0, 0))
zi.compress_type = zipfile.ZIP_STORED
zi.extra = b'\0\0\0'
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_STORED) as o:
    o.writestr(zi, bytes(d))
out = open(sys.argv[2], 'rb').read()
assert out[44:48] == b'dex\n', 'classes.dex not at offset 44'
print('unit sdk patched: dex', dex_md5, 'jar', hashlib.md5(out).hexdigest())
