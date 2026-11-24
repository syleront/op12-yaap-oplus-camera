# Install script, sourced by the KernelSU / Magisk / APatch installer ($MODPATH = new module dir)
MODDIR=$MODPATH
. $MODPATH/common.sh

if [ "$APATCH" = true ]; then MGR=APatch
elif [ "$KSU" = true ]; then MGR=KernelSU
elif [ -n "$MAGISK_VER_CODE" ]; then MGR=Magisk
else abort "! Install this module from the KernelSU, Magisk or APatch app"; fi
[ "$BOOTMODE" = true ] || abort "! Install from the $MGR app (flashing in recovery is not supported)"
ui_print "- Root: $MGR"
[ "$ARCH" = arm64 ] || abort "! arm64 only"
if ! reason=$(preflight); then
    ui_print "! $reason"
    ui_print "  ($(rom_info))"
    abort "! Nothing installed"
fi
if [ "$(rom_id)" = yaap ]; then
    ui_print "- ROM: YAAP"
else
    ui_print "- ROM: $(rom_name) (EXPERIMENTAL: only tested on YAAP)"
    ui_print "  Please report the result, with /data/adb/opcamera/log.txt"
fi
# (our own camera, if an older version of this module is active, doesn't count: its mounts are "opcamera")
[ -d /system_ext/priv-app/OplusCamera ] &&
    ! awk '{ for (i = 7; i <= NF; i++) if ($i == "-") break; if ($(i+2) == "opcamera") f = 1 } END { exit !f }' /proc/1/mountinfo &&
    abort "! This ROM already has the OnePlus camera"

ui_print "- Checking files"
( cd $MODPATH/files && sha256sum -c ../sha256.txt >/dev/null 2>&1 ) || abort "! Corrupted download (checksum mismatch), nothing installed"

ui_print "- Setting permissions and SELinux labels"
apply_labels
labels_ok || abort "! Could not set SELinux labels"

# Kernels that refuse /data folders as overlay layers: pack the files into an ext4 image (common.sh)
if ! overlay_ok $F; then
    ui_print "- This kernel can't overlay files from /data: packing them into an image"
    ui_print "  (needs ~1 GB free space, takes a minute)"
    if ! img_build; then
        mkdir -p $ST; log E "install: image failed: $IMG_ERR"
        ui_print "! Could not create the image:"
        echo "$IMG_ERR" | fold -w 60 | while read -r l; do ui_print "  $l"; done
        abort "! Nothing installed (details also in /data/adb/opcamera/log.txt)"
    fi
fi

mkdir -p $ST
rm -f $ST/hal_mode $ST/10bit.orig $ST/rom   # v1.x: HAL switch state
getprop ro.build.fingerprint > $ST/fingerprint
rm -f $ST/boot_pending
rm -f $MODPATH/sha256.txt

# v1.x had a Camera HAL switch app (tile + icon); there is only the ROM's HAL now
if pm path com.syleront.opcamera.halswitch >/dev/null 2>&1; then
    ui_print "- Removing the Camera HAL switch app (not needed any more)"
    pm uninstall com.syleront.opcamera.halswitch >/dev/null 2>&1
fi

# The OnePlus gallery ships as a system app; a copy installed as a normal app would shadow it
# (it'd run without the camera's SELinux rules and its editor crashes).
if pm path com.oneplus.gallery 2>/dev/null | grep -q '^package:/data/app/' &&
   ! pm path com.oneplus.gallery 2>/dev/null | grep -q '/priv-app/'; then
    ui_print "- Removing the separately installed OnePlus gallery (the module provides it)"
    pm uninstall com.oneplus.gallery >/dev/null 2>&1
fi

ui_print "- The OnePlus camera runs on the $(rom_name) camera HAL"
[ -f $IMG ] && rm -rf $MODPATH/files   # everything is in the image now
ui_print "- Reboot to activate."
ui_print "  If the phone doesn't finish booting, it disables this module and reboots"
ui_print "  by itself after ~5 min. Or force a reboot (hold Power + Vol Up + Vol Down),"
ui_print "  and the module turns itself off."
