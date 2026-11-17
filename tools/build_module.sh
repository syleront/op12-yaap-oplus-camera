#!/bin/sh
# Builds build/opcamera_yaap-<version>.zip from module/ + payload/ + build artifacts.
set -e
cd "$(dirname "$0")/.."
R=$PWD; O=build/module
VER=$(grep ^version= module/module.prop | cut -d= -f2)
rm -rf $O; mkdir -p $O/files/sys $O/files/hal $O/bin
cp -r module/. $O/
cp -r payload/cameraserver/system payload/cameraserver/system_ext $O/files/sys/
cp -r payload/app/system_ext/. $O/files/sys/system_ext/
tar -xf payload/hal.tar -C $O/files/hal
cp build/bin/binderpatch $O/bin/
cp tools/gen/labels.txt $O/files/labels.txt
# HAL switch app (quick settings tile + launcher icon), installed by customize.sh
cp build/halswitch/HalSwitch.apk $O/files/HalSwitch.apk
# lens-row fix overlay (src/zoomfix, built non-static so it can be toggled live)
mkdir -p $O/files/sys/product/overlay/OPCameraZoomFix
cp build/zoomfix/zoomfix_static_false.apk $O/files/sys/product/overlay/OPCameraZoomFix/OPCameraZoomFix.apk
for p in sys/product sys/product/overlay sys/product/overlay/OPCameraZoomFix sys/product/overlay/OPCameraZoomFix/OPCameraZoomFix.apk; do echo "u:object_r:system_file:s0 $p"; done >> $O/files/labels.txt

# checks: patched blobs are the tested ones, every payload file has a tested label,
# no shipped APK uses a shared system uid (that bootlooped before)
check_md5() { [ "$(md5sum "$1" | cut -d' ' -f1)" = "$2" ] || { echo "md5 mismatch: $1"; exit 1; }; }
check_md5 $O/files/hal/odm/lib64/libAlgoProcess.so 68fc7841b75b62d0369c7db90a9832e8
check_md5 $O/files/hal/odm/lib64/libapsfix.so 91b2bdfe5e71c2a77ecf89306f138b73
missing=$(cd $O/files && find sys hal -mindepth 1 | while read p; do grep -q " $p\$" labels.txt || echo "$p"; done)
[ -z "$missing" ] || { echo "no tested label for:"; echo "$missing"; exit 1; }
AAPT2=$(ls -d /c/Users/Syleront/AppData/Local/Android/Sdk/build-tools/*/aapt2.exe | tail -1)
for apk in $(find $O/files -name '*.apk'); do
    if "$AAPT2" dump xmltree --file AndroidManifest.xml "$apk" | grep -q sharedUserId; then
        echo "REFUSING: $apk has sharedUserId"; "$AAPT2" dump xmltree --file AndroidManifest.xml "$apk" | grep sharedUserId; exit 1
    fi
done
(cd $O/files && find . -type f ! -name labels.txt | sort | xargs sha256sum | awk '{f=$2; sub(/^[*]/, "", f); print $1 "  " f}') > $O/sha256.txt
for s in $O/*.sh $O/module.prop $O/sepolicy.rule $O/META-INF/com/google/android/update-binary; do
    grep -q $'\r' "$s" && { echo "CRLF in $s"; exit 1; }
done

ZIP=build/opcamera_yaap-$VER.zip; rm -f $ZIP
MSYS_NO_PATHCONV=1 wsl -e python3 - "/mnt$R" "$VER" <<'PY'
import os, sys, zipfile
root, ver = sys.argv[1], sys.argv[2]
src = os.path.join(root, 'build/module'); dst = os.path.join(root, f'build/opcamera_yaap-{ver}.zip')
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for d, _, fs in os.walk(src):
        for f in sorted(fs):
            p = os.path.join(d, f); a = os.path.relpath(p, src)
            zi = zipfile.ZipInfo.from_file(p, a); zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if a.endswith('.sh') or a.startswith('bin/') else 0o644) << 16
            with open(p, 'rb') as fh: z.writestr(zi, fh.read())
print('zip ok', dst)
PY
ls -la $ZIP; md5sum $ZIP
