#!/usr/bin/env bash
# Makes the OnePlus camera APK usable on YAAP, then re-signs it:
#   - manifest: adds <uses-library android:name="oplus.fwk" android:required="false"/> (tools/axmlpatch.py;
#     files/.../oplus_fwk_library.xml provides that library);
#   - classes12.dex (through baksmali/smali): hides the Hi-Res and Pro video modes (tools/patch_modelist.py,
#     class xm/e) and the Video mode's HDR / Dolby Vision switch (tools/patch_videohdr.py, com/oplus/camera/module/a).
# usage: tools/repack_camera_apk.sh <DerpFest OplusCamera.apk> <out.apk>
#
# Needs SMALI_JAR: a jar with both smali and baksmali (com.android.tools.smali.{smali,baksmali}.Main), e.g.
# jadx-<version>-all.jar (jadx/lib) or a smali + baksmali fat jar.
# smali's dex layout isn't reproducible (thread order), so the result is checked by disassembling it again:
# every class must match the input except the patched ones, which must match the tested patches.
#
# Signing: KEYSTORE/KS_PASS/KS_ALIAS (default: the Android debug key). Releases since v2.0.5 are signed with the
# maintainer's opcamera-release key; another key works the same (Android 17 keeps a system app's data when its
# signature changes: "System package ... signature changed; retaining data").
set -e
. "$(dirname "$0")/env.sh"
[ $# = 2 ] || die "usage: $0 <OplusCamera.apk> <out.apk>"
[ -n "${SMALI_JAR:-}" ] && [ -f "$SMALI_JAR" ] || die "set SMALI_JAR to a jar with smali and baksmali (e.g. jadx-*-all.jar)"
IN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2
JAVA=$JAVA_HOME_U/bin/java$X
T=$R/build/repack; rm -rf "$T"; mkdir -p "$T"
check_md5 "$IN" 81f77c9ad16088ad03fff44af344fa56      # DerpFest 2026-10-05 / 2026-11-15 OplusCamera.apk
xz() { py -c "import zipfile,sys; open(sys.argv[3],'wb').write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))" "$(hp "$IN")" "$1" "$(hp "$2")"; }
bak() { "$JAVA" -Xmx4g -cp "$(wpath "$SMALI_JAR")" com.android.tools.smali.baksmali.Main d -o "$(wpath "$2")" "$(wpath "$1")"; }
sma() { "$JAVA" -Xmx4g -cp "$(wpath "$SMALI_JAR")" com.android.tools.smali.smali.Main a --api 28 -o "$(wpath "$2")" "$(wpath "$1")"; }

# manifest
xz AndroidManifest.xml "$T/AndroidManifest.orig.xml"
py "$(hp "$R/tools/axmlpatch.py")" "$(hp "$T/AndroidManifest.orig.xml")" "$(hp "$T/AndroidManifest.xml")"

# classes12.dex: mode list (xm/e), Video HDR switch (com/oplus/camera/module/a)
# <class> <patcher> <md5 of the patched class, disassembled again, CR stripped>
PATCHES="xm/e patch_modelist.py e9738ba4211d25093609d4bd006b93db
com/oplus/camera/module/a patch_videohdr.py 7e2cdb6b2f1489f3b7c09de9a9fd9944"
xz classes12.dex "$T/classes12.orig.dex"
check_md5 "$T/classes12.orig.dex" 4151b8d69cb9ccfe8b0d5cf1d6470ffe
bak "$T/classes12.orig.dex" "$T/s"
want=
while read -r c p m; do
    mkdir -p "$T/orig/$(dirname "$c")"; cp "$T/s/$c.smali" "$T/orig/$c.smali"
    py "$(hp "$R/tools/$p")" "$(hp "$T/s/$c.smali")"
    want="$want${want:+
}Files $T/s/$c.smali and $T/v/$c.smali differ"
done <<< "$PATCHES"
sma "$T/s" "$T/classes12.dex"
bak "$T/classes12.dex" "$T/v"
cp -r "$T/orig/." "$T/s/"                             # compare everything else with the unpatched input
d=$(diff -r -q --strip-trailing-cr "$T/s" "$T/v" || true)
[ "$(echo "$d" | sort)" = "$(echo "$want" | sort)" ] || die "classes12.dex: unexpected differences: $d"
while read -r c p m; do
    got=$(tr -d '\r' < "$T/v/$c.smali" | md5sum | cut -d' ' -f1)
    [ "$got" = "$m" ] || die "classes12.dex: $c is not the tested patch ($got)"
done <<< "$PATCHES"
echo "classes12.dex patched (modes and Video HDR hidden), verified"

py "$(hp "$R/tools/apkrepack.py")" "$(hp "$IN")" "$(hp "$T/AndroidManifest.xml")" "$(hp "$T/unaligned.apk")" \
    "classes12.dex=$(hp "$T/classes12.dex")"
"$ZIPALIGN" -P 16 -f 4 "$T/unaligned.apk" "$T/aligned.apk"
apksign "$T/aligned.apk" "$OUT"
rm -f "$OUT.idsig"
rm -rf "$T/s" "$T/v" "$T/orig"
ls -l "$OUT"
