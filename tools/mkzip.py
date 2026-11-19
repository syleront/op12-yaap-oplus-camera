# Zips the assembled module dir reproducibly: mkzip.py <dir> <out.zip>
# Scripts and bin/ are 0755, everything else 0644; entries sorted, fixed timestamps.
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
entries = []
for d, _, fs in os.walk(src):
    for f in fs:
        p = os.path.join(d, f)
        entries.append((os.path.relpath(p, src).replace(os.sep, '/'), p))
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for a, p in sorted(entries):
        zi = zipfile.ZipInfo(a, date_time=(2008, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = (0o100755 if a.endswith('.sh') or a.startswith('bin/') else 0o100644) << 16
        with open(p, 'rb') as fh:
            z.writestr(zi, fh.read())
print('zip ok', dst)
