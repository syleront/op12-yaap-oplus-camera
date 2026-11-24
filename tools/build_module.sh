#!/usr/bin/env bash
# Assembles build/opcamera_yaap-<version>.zip from module/ + files/ + payload/ + build/{native,zoomfix}.
# Run tools/build.sh (or build_native.sh + build_apps.sh first). See docs/BUILDING.md.
set -e
. "$(dirname "$0")/env.sh"
cd "$R"
O=build/module

VER=$(grep ^version= module/module.prop | cut -d= -f2)
# semver vMAJOR.MINOR.PATCH; versionCode = MAJOR*10000 + MINOR*100 + PATCH (KernelSU compares the code)
echo "$VER" | grep -Eq '^v[0-9]+\.[0-9]{1,2}\.[0-9]{1,2}$' || die "version must be vMAJOR.MINOR.PATCH (minor/patch < 100): $VER"
CODE=$(echo "${VER#v}" | awk -F. '{print $1*10000 + $2*100 + $3}')
[ "$(grep ^versionCode= module/module.prop | cut -d= -f2)" = "$CODE" ] || die "versionCode must be $CODE for $VER"

# --- payload: exactly the tested DerpFest files (payload/MANIFEST.sha256, see docs/PAYLOAD.md)
APK=sys/system_ext/priv-app/OplusCamera/OplusCamera.apk
bad=$(cd payload && sha256sum -c MANIFEST.sha256 2>/dev/null | grep -v ': OK$' || true)
missing=$(echo "$bad" | grep -v "^$APK: FAILED$" | grep . || true)
[ -z "$missing" ] || die "payload differs from payload/MANIFEST.sha256 (run tools/extract_payload.sh):
$missing"
[ -z "$bad" ] || echo "warning: $APK is not the release build (re-signed with another key?)."
extra=$(cd payload && find sys hal -type f | while read -r p; do grep -q "  $p\$" MANIFEST.sha256 || echo "$p"; done)
[ -z "$extra" ] || die "files in payload/ that are not in MANIFEST.sha256:
$extra"
for f in build/native/binderpatch build/native/relink build/native/libapsfix.so build/native/libcsext_shim.so \
         build/native/libheiffix.so build/native/cave.bin build/zoomfix/OPCameraZoomFix.apk; do
    [ -f "$f" ] || die "missing $f (run tools/build.sh)"
done

rm -rf $O; mkdir -p $O/files $O/bin
cp -r module/. $O/
cp -r payload/sys $O/files/
cp -r files/sys/. $O/files/sys/          # our own permission/sysconfig XMLs
# HAL side: only what the OnePlus camera needs on top of the ROM's own (OnePlus) camera HAL
# libYTCommon.so: YAAP's copy (OCR, text mode) has its program headers moved out of the loadable segments
# by patchelf, which the linker rejects; DerpFest's has the same code and data, laid out correctly
for p in odm/lib64/libOplusSecurity.so odm/lib64/libOPAlgoCamFaceBeautyCap.so \
         odm/lib64/libYTCommon.so \
         odm/etc/camera/license_release_fdc.lic odm/etc/camera/model/license.lic \
         odm/etc/camera/singleblur/license_release.license \
         odm/etc/camera/config/oplus_camera_aps_config odm/etc/camera/config/oplus_camera_algo_switch_config; do
    mkdir -p $O/files/hal/${p%/*}; cp payload/hal/$p $O/files/hal/$p
done
# DerpFest's libui-stock.so (OnePlus's libui) as libus.so: same name length as libui.so, so the ROM's
# HAL libraries that need it are relinked on the phone by renaming one string (src/relink)
mkdir -p $O/files/hal/vendor/lib64; cp payload/hal/vendor/lib64/libui-stock.so $O/files/hal/vendor/lib64/libus.so

# --- patched DerpFest binaries (each patcher refuses unknown input and checks its result)
# cameraserver: the OnePlus camera evicts other camera apps instead of sharing the HAL (src/evictfix);
# NULL physical-camera result metadata (portrait); OnePlus-camera-only characteristics (src/csfix, src/shim)
T=build/tmp; rm -rf $T; mkdir -p $T
py "$(hp "$R/tools/patch_cameraserver.py")" "$(hp "$R/payload/sys/system/bin/cameraserver")" \
   "$(hp "$R/$T/cs1")" "$(hp "$R/build/native/cave.bin")"
py "$(hp "$R/tools/patch_cs_physmeta.py")" "$(hp "$R/$T/cs1")" "$(hp "$R/$T/cs2")"
py "$(hp "$R/tools/patch_cs_chars.py")" "$(hp "$R/$T/cs2")" "$(hp "$R/$O/files/sys/system/bin/cameraserver")"
# libcsextimpl.so: + NEEDED libcsext_shim.so (src/shim); patchelf 0.18 gives the tested file
L=$O/files/sys/system_ext/lib64/libcsextimpl.so
pelf --add-needed libcsext_shim.so "$(hp "$R/$L")"
check_md5 $L 6ab7b16614f418fdd71a9ef727877c88
# libAPSClient-cmd-jni.so: + NEEDED libheiffix.so (src/heiffix: HEIC parameter names)
L=$O/files/sys/system_ext/lib64/libAPSClient-cmd-jni.so
pelf --add-needed libheiffix.so "$(hp "$R/$L")"
check_md5 $L 4110a2bd9e6714e7d80a0c5affa892e4
# libAlgoProcess.so: P010 planes (src/apsfix), HEIC EXIF; offline-reprocess crop (src/apscrop)
py "$(hp "$R/tools/patch_algoprocess.py")" "$(hp "$R/payload/hal/odm/lib64/libAlgoProcess.so")" "$(hp "$R/$T/aps1")"
py "$(hp "$R/tools/patch_apscrop.py")" "$(hp "$R/$T/aps1")" "$(hp "$R/$O/files/hal/odm/lib64/libAlgoProcess.so")"
# libAlgoInterface.so: textEnhanceUninit() null check (crashed the camera when it closed)
py "$(hp "$R/tools/patch_algointerface.py")" "$(hp "$R/payload/hal/odm/lib64/libAlgoInterface.so")" \
   "$(hp "$R/$O/files/hal/odm/lib64/libAlgoInterface.so")"
# com.oplus.camera.unit.sdk.jar: Hi-Res (1x) raw outputs at the picture size (tools/patch_unitsdk.py)
py "$(hp "$R/tools/patch_unitsdk.py")" "$(hp "$R/payload/sys/system_ext/framework/com.oplus.camera.unit.sdk.jar")" \
   "$(hp "$R/$O/files/sys/system_ext/framework/com.oplus.camera.unit.sdk.jar")"
rm -rf $T

# --- our own builds
cp build/native/libcsext_shim.so $O/files/sys/system_ext/lib64/
cp build/native/libheiffix.so $O/files/sys/system_ext/lib64/
cp build/native/libapsfix.so $O/files/hal/odm/lib64/
cp build/native/binderpatch build/native/relink $O/bin/
mkdir -p $O/files/sys/product/overlay/OPCameraZoomFix
cp build/zoomfix/OPCameraZoomFix.apk $O/files/sys/product/overlay/OPCameraZoomFix/OPCameraZoomFix.apk
# labels of the shipped paths only
(cd $O/files && find sys hal -mindepth 1) | LC_ALL=C sort > build/paths.txt
awk 'NR == FNR { want[$0] = 1; next } ($2 in want)' build/paths.txt tools/labels.txt > $O/files/labels.txt
rm -f build/paths.txt

# --- checks: the patched blobs are the tested ones, every file has a tested SELinux label,
# no shipped APK uses a shared system uid (that bootlooped before)
check_md5 $O/files/sys/system/bin/cameraserver 422b3f12ad05c89a83d1690492777ca8
check_md5 $O/files/hal/odm/lib64/libAlgoProcess.so 7ccb448871edee6838b692d1acbaf2f4
check_md5 $O/files/hal/odm/lib64/libAlgoInterface.so 469073d3e2bca886fb3cab5b9aec4b58
check_md5 $O/files/sys/system_ext/framework/com.oplus.camera.unit.sdk.jar c7ceb6dec720076d983523506f146284
check_md5 $O/files/hal/odm/lib64/libapsfix.so 9afaa67575bf21779ddd3e782dc073ef
check_md5 $O/files/sys/system_ext/lib64/libcsext_shim.so eb557ca92727ffd0e092008b1884a38a
check_md5 $O/files/sys/system_ext/lib64/libheiffix.so 3935e12d99086489cf2a20be3a5ca76c
missing=$(cd $O/files && find sys hal -mindepth 1 | while read -r p; do grep -q " $p\$" labels.txt || echo "$p"; done)
[ -z "$missing" ] || die "no tested label for:
$missing"
for apk in $(find $O/files -name '*.apk'); do
    if "$AAPT2" dump xmltree --file AndroidManifest.xml "$apk" | grep -q sharedUserId; then
        die "REFUSING: $apk has sharedUserId"
    fi
done
(cd $O/files && find . -type f ! -name labels.txt | LC_ALL=C sort | xargs sha256sum | awk '{f=$2; sub(/^[*]/, "", f); print $1 "  " f}') > $O/sha256.txt
for s in $O/*.sh $O/module.prop $O/sepolicy.rule $O/META-INF/com/google/android/update-binary; do
    if grep -q $'\r' "$s"; then die "CRLF in $s"; fi
done

ZIP=build/opcamera_yaap-$VER.zip
[ ! -f $ZIP ] || [ -n "${FORCE:-}" ] || die "$ZIP already exists (bump the version, or FORCE=1 to overwrite)"
rm -f $ZIP
py "$(hp "$R/tools/mkzip.py")" "$(hp "$R/$O")" "$(hp "$R/$ZIP")"
ls -la $ZIP; md5sum $ZIP
