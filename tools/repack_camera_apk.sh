#!/usr/bin/env bash
# Makes the OnePlus camera APK usable on YAAP: adds
#   <uses-library android:name="oplus.fwk" android:required="false"/>
# to its manifest (tools/axmlpatch.py; files/.../oplus_fwk_library.xml provides that library), then
# re-signs it. usage: tools/repack_camera_apk.sh <DerpFest OplusCamera.apk> <out.apk>
#
# The released module's APK is signed with the maintainer's key, so a build signed with another key
# (KEYSTORE/KS_PASS/KS_ALIAS, default: the Android debug key) differs from payload/MANIFEST.sha256.
# It works the same, but switching between such builds resets the camera's app data.
set -e
. "$(dirname "$0")/env.sh"
[ $# = 2 ] || die "usage: $0 <OplusCamera.apk> <out.apk>"
IN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2
T=$R/build/repack; rm -rf "$T"; mkdir -p "$T"
check_md5 "$IN" 81f77c9ad16088ad03fff44af344fa56      # DerpFest 2026-10-05 / 2026-11-15 OplusCamera.apk
py -c "import zipfile,sys; open(sys.argv[2],'wb').write(zipfile.ZipFile(sys.argv[1]).read('AndroidManifest.xml'))" \
    "$(hp "$IN")" "$(hp "$T/AndroidManifest.orig.xml")"
py "$(hp "$R/tools/axmlpatch.py")" "$(hp "$T/AndroidManifest.orig.xml")" "$(hp "$T/AndroidManifest.xml")"
py "$(hp "$R/tools/apkrepack.py")" "$(hp "$IN")" "$(hp "$T/AndroidManifest.xml")" "$(hp "$T/unaligned.apk")"
"$ZIPALIGN" -P 16 -f 4 "$T/unaligned.apk" "$T/aligned.apk"
apksign "$T/aligned.apk" "$OUT"
rm -f "$OUT.idsig"
ls -l "$OUT"
