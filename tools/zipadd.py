# Adds a file to a zip with a fixed timestamp (reproducible builds): zipadd.py <zip> <file> <name-in-zip>
import sys, zipfile
info = zipfile.ZipInfo(sys.argv[3], date_time=(2008, 1, 1, 0, 0, 0))
info.compress_type = zipfile.ZIP_DEFLATED
with zipfile.ZipFile(sys.argv[1], 'a') as z, open(sys.argv[2], 'rb') as f:
    z.writestr(info, f.read())
