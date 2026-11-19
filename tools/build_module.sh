#!/usr/bin/env bash
# Assembles build/opcamera_yaap-<version>.zip from module/ + files/ + payload/ + build/{native,halswitch,zoomfix}.
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
[ -z "$bad" ] || echo "warning: $APK is not the release build (re-signed with another key?). Users switching between
         your build and the release one will get the camera's app data reset."
extra=$(cd payload && find sys hal -type f | while read -r p; do grep -q "  $p\$" MANIFEST.sha256 || echo "$p"; done)
[ -z "$extra" ] || die "files in payload/ that are not in MANIFEST.sha256:
$extra"
for f in build/native/binderpatch build/native/libapsfix.so build/native/libcsext_shim.so build/native/cave.bin \
         build/halswitch/HalSwitch.apk build/zoomfix/OPCameraZoomFix.apk; do
    [ -f "$f" ] || die "missing $f (run tools/build.sh)"
done

rm -rf $O; mkdir -p $O/files $O/bin
cp -r module/. $O/
cp -r payload/sys payload/hal $O/files/
cp -r files/sys/. $O/files/sys/          # our own permission/sysconfig XMLs

# --- patched DerpFest binaries (each patcher refuses unknown input and checks its result)
# cameraserver: the OnePlus camera evicts other camera apps instead of sharing the HAL (src/evictfix)
py "$(hp "$R/tools/patch_cameraserver.py")" "$(hp "$R/payload/sys/system/bin/cameraserver")" \
   "$(hp "$R/$O/files/sys/system/bin/cameraserver")" "$(hp "$R/build/native/cave.bin")"
# libcsextimpl.so: + NEEDED libcsext_shim.so (src/shim); patchelf 0.18 gives the tested file
L=$O/files/sys/system_ext/lib64/libcsextimpl.so
pelf --add-needed libcsext_shim.so "$(hp "$R/$L")"
check_md5 $L 6ab7b16614f418fdd71a9ef727877c88
# libAlgoProcess.so: YAAP's AHardwareBuffer_lockPlanes returns one plane for P010 (src/apsfix)
py "$(hp "$R/tools/patch_algoprocess.py")" "$(hp "$R/payload/hal/odm/lib64/libAlgoProcess.so")" \
   "$(hp "$R/$O/files/hal/odm/lib64/libAlgoProcess.so")"

# --- our own builds
cp build/native/libcsext_shim.so $O/files/sys/system_ext/lib64/
cp build/native/libapsfix.so $O/files/hal/odm/lib64/
cp build/native/binderpatch $O/bin/
cp build/halswitch/HalSwitch.apk $O/files/HalSwitch.apk         # installed by customize.sh
mkdir -p $O/files/sys/product/overlay/OPCameraZoomFix
cp build/zoomfix/OPCameraZoomFix.apk $O/files/sys/product/overlay/OPCameraZoomFix/OPCameraZoomFix.apk
cp tools/labels.txt $O/files/labels.txt

# --- checks: the patched blobs are the tested ones, every file has a tested SELinux label,
# no shipped APK uses a shared system uid (that bootlooped before)
check_md5 $O/files/sys/system/bin/cameraserver ca45c8570630cb84800c7775200620d3
check_md5 $O/files/hal/odm/lib64/libAlgoProcess.so 68fc7841b75b62d0369c7db90a9832e8
check_md5 $O/files/hal/odm/lib64/libapsfix.so 91b2bdfe5e71c2a77ecf89306f138b73
check_md5 $O/files/sys/system_ext/lib64/libcsext_shim.so ea248c50ef1e262800e43efebf843dbc
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
