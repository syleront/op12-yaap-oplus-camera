# Rebuilds an APK with a replaced AndroidManifest.xml (and optionally other replaced entries, e.g. a patched
# classesN.dex), dropping the old signature (META-INF/*.SF/.RSA/...); every other entry is copied as is (same
# order, compression and timestamps). zipalign + sign afterwards.
# usage: apkrepack.py <in.apk> <AndroidManifest.xml> <out.apk> [<entry>=<file> ...]
import sys, zipfile
src, manifest, dst = sys.argv[1:4]
repl = {'AndroidManifest.xml': open(manifest, 'rb').read()}
for a in sys.argv[4:]:
    name, path = a.split('=', 1)
    repl[name] = open(path, 'rb').read()
seen = set()
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w') as zo:
    for it in zi.infolist():
        n = it.filename
        if n.count('/') == 1 and n.startswith('META-INF/') and n.rsplit('.', 1)[-1].upper() in ('SF', 'RSA', 'DSA', 'EC', 'MF'):
            continue
        out = zipfile.ZipInfo(n, date_time=it.date_time)
        out.compress_type = it.compress_type; out.external_attr = it.external_attr
        if n in repl:
            seen.add(n)
        zo.writestr(out, repl[n] if n in repl else zi.read(n))
missing = set(repl) - seen
if missing:
    sys.exit('apkrepack: not in %s: %s' % (src, ', '.join(sorted(missing))))
print('repacked', dst)
