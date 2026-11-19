#!/system/bin/sh
# Live (non-persistent) test of Stage B: OPlus camera app + framework bits.
# Requires Stage A (live_cs.sh up) for the cameraserver extension, but works without it.
# Nothing survives a hard reboot. After "up", do a soft reboot (stop; start) so
# PackageManager scans the new system apps.
#   sh live_app.sh up | down | status

SRC=/data/local/tmp/opc_push/app
S=/data/adb/opc_live/app
NS="nsenter -t 1 -m --"
DIRS="priv-app app framework etc/permissions etc/default-permissions etc/sysconfig lib64"

status() {
    echo "--- app overlays (init ns)"
    grep "opc_live/app" /proc/1/mountinfo | awk '{print $5}'
    pm path com.oplus.camera 2>/dev/null
}

up() {
    [ -d "$SRC/system_ext" ] || { echo "payload missing at $SRC"; exit 1; }
    if grep -q "opc_live/app" /proc/1/mountinfo; then echo "already up"; status; exit 0; fi
    rm -rf "$S"; mkdir -p "$S"; cp -a "$SRC/." "$S/"
    chown -R 0:0 "$S"
    find "$S" -type d -exec chmod 0755 {} \;
    find "$S" -type f -exec chmod 0644 {} \;
    chcon -R u:object_r:system_file:s0 "$S/system_ext"
    chcon -R u:object_r:system_lib_file:s0 "$S/system_ext/lib64"
    for d in $DIRS; do
        src="$S/system_ext/$d"; tgt="/system_ext/$d"
        [ -d "$src" ] || continue
        # stacks on top of an existing overlay (e.g. Stage A on lib64) if present
        $NS mount -t overlay -o "lowerdir=$src:$tgt" overlay "$tgt" && echo "overlay ok: $tgt" || { echo "FAIL: $tgt"; down; exit 1; }
    done
    resetprop -n persist.vendor.camera.privapp.list com.oplus.camera
    resetprop -n ro.oplus.system.camera.name com.oplus.camera
    resetprop -n ro.com.google.lens.oem_camera_package com.oplus.camera
    resetprop -n ro.com.google.lens.oem_image_package com.oneplus.gallery
    resetprop -n ro.vendor.oplus.market.name "OnePlus 12"
    resetprop -n ro.vendor.oplus.market.enname "OnePlus 12"
    resetprop -n ro.vendor.oplus.market.watermark "OnePlus 12"
    ls -l /system_ext/priv-app/OplusCamera/ /system_ext/framework/oplus-fwk.jar
    echo "Now soft-reboot: stop; start"
}

down() {
    # reverse order, top-most first; lazy so busy mounts detach cleanly
    for d in lib64 etc/sysconfig etc/default-permissions etc/permissions framework app priv-app; do
        grep -q "lowerdir=$S/system_ext/$d:" /proc/1/mountinfo && $NS umount -l "/system_ext/$d"
    done
    rm -rf "$S"
    status
    echo "Soft-reboot (stop; start) or hard reboot to make PackageManager forget the app."
}

case "$1" in
    up) up ;;
    down) down ;;
    *) status ;;
esac
