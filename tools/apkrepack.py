# Rebuilds an APK with a replaced AndroidManifest.xml, dropping the old signature (META-INF/*.SF/.RSA/...);
# every other entry is copied as is (same order, compression and timestamps). zipalign + sign afterwards.
# usage: apkrepack.py <in.apk> <AndroidManifest.xml> <out.apk>
import sys, zipfile
src, manifest, dst = sys.argv[1:4]
new = open(manifest, 'rb').read()
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w') as zo:
    for it in zi.infolist():
        n = it.filename
        if n.count('/') == 1 and n.startswith('META-INF/') and n.rsplit('.', 1)[-1].upper() in ('SF', 'RSA', 'DSA', 'EC', 'MF'):
            continue
        out = zipfile.ZipInfo(n, date_time=it.date_time)
        out.compress_type = it.compress_type; out.external_attr = it.external_attr
        zo.writestr(out, new if n == 'AndroidManifest.xml' else zi.read(n))
print('repacked', dst)
