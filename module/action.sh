#!/system/bin/sh
# KernelSU "Action" button: switch the camera HAL (OnePlus <-> YAAP). The choice is remembered
# across reboots. From a root shell:  sh action.sh [oos|yaap|status]
MODDIR=${0%/*}
. $MODDIR/common.sh

if [ ! -f $ACTIVE ]; then
    echo "The module is not active this boot, nothing to switch."
    echo "Log: $LOG"; tail -n 5 $LOG 2>/dev/null; exit 1
fi
cur=$(hal_cur)
case "$1" in
    status) echo "Camera HAL: $(hal_name $cur) (boot default: $(hal_name $(hal_mode)))"; exit 0 ;;
    oos|yaap) tgt=$1 ;;
    *) [ $cur = oos ] && tgt=yaap || tgt=oos ;;
esac
echo "Camera HAL now: $(hal_name $cur)"
if [ $tgt = $cur ]; then echo $tgt > $ST/hal_mode; echo "Already on it."; exit 0; fi

mkdir $LOCK 2>/dev/null || { echo "A switch is already running."; exit 1; }
trap 'rmdir $LOCK' EXIT

if cam_busy; then
    echo ""; echo "A camera app has the camera open right now."
    echo "Close it (swipe it away from recents) and press Action again."; exit 1
fi
# the OnePlus camera can't run on the YAAP HAL; don't leave it in the background
[ $tgt = yaap ] && am force-stop $OPLUS

echo "Switching to $(hal_name $tgt)... (camera is unavailable for ~6 s)"
s=$(awk '{print int($1)}' /proc/uptime)
hal_switch $tgt; r=$?
e=$(awk '{print int($1)}' /proc/uptime)
now=$(hal_cur)
[ $r = 0 ] && [ $now = $tgt ] && echo $tgt > $ST/hal_mode
log I "action: $cur -> $tgt, now $now, rc=$r, $((e-s))s"
desc_active
echo ""
echo "Camera HAL: $(hal_name $now) ($((e-s)) s)"
cams_ready && echo "Cameras ready." || echo "Cameras not listed yet, give it a few seconds."
if [ $now = oos ]; then
    echo "OnePlus camera: ready to use. This stays after reboots."
else
    echo "OnePlus camera: don't open it on this HAL (it will close itself). This stays after reboots."
fi
