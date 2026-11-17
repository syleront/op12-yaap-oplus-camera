# KernelSU install script (sourced by the installer; $MODPATH = new module dir)
MODDIR=$MODPATH
. $MODPATH/common.sh

[ "$KSU" = true ] || abort "! This module is for KernelSU only"
[ "$ARCH" = arm64 ] || abort "! arm64 only"
reason=$(preflight) || abort "! $reason"
[ -d /system_ext/priv-app/OplusCamera ] && ! grep -q "lowerdir=/data/adb/" /proc/1/mountinfo &&
    abort "! This ROM already has the OnePlus camera"

ui_print "- Checking files"
( cd $MODPATH/files && sha256sum -c ../sha256.txt >/dev/null 2>&1 ) || abort "! Corrupted download (checksum mismatch), nothing installed"

ui_print "- Setting permissions and SELinux labels"
apply_labels
labels_ok || abort "! Could not set SELinux labels"

mkdir -p $ST
[ -f $ST/hal_mode ] || echo oos > $ST/hal_mode
getprop ro.build.fingerprint > $ST/fingerprint
rm -f $ST/boot_pending
rm -f $MODPATH/sha256.txt

ui_print "- Camera HAL at boot: $(hal_name $(hal_mode))"
ui_print "  (press the module's Action button to switch)"
ui_print "- Reboot to activate."
ui_print "  If the phone doesn't finish booting, it disables this module and reboots"
ui_print "  by itself after ~5 min. Or force a reboot (hold Power + Volume Up),"
ui_print "  and the module turns itself off."
