#!/system/bin/sh
# KernelSU "Action" button: switch the camera HAL (OnePlus <-> YAAP). The choice is remembered
# across reboots. From a root shell:  sh action.sh [oos|yaap|status]
# For the HAL switch app (one-line answers):  sh action.sh get | app-toggle | app-oos | app-yaap
#   get        -> oos | yaap | inactive
#   app-*      -> "ok <hal>" | "busy" | "inactive" | "locked" | "fail <hal>"
MODDIR=${0%/*}
. $MODDIR/common.sh

APP=0
case "$1" in
    get) [ -f $ACTIVE ] && hal_cur || echo inactive; exit 0 ;;
    app-*) APP=1 ;;
esac
say() { [ $APP = 0 ] && echo "$@"; }

if [ ! -f $ACTIVE ]; then
    [ $APP = 1 ] && { echo inactive; exit 1; }
    echo "The module is not active this boot, nothing to switch."
    echo "Log: $LOG"; tail -n 5 $LOG 2>/dev/null; exit 1
fi
cur=$(hal_cur)
case "$1" in
    status) echo "Camera HAL: $(hal_name $cur) (boot default: $(hal_name $(hal_mode)))"; exit 0 ;;
    oos|yaap|app-oos|app-yaap) tgt=${1#app-} ;;
    *) [ $cur = oos ] && tgt=yaap || tgt=oos ;;
esac
say "Camera HAL now: $(hal_name $cur)"
if [ $tgt = $cur ]; then
    echo $tgt > $ST/hal_mode; [ $APP = 1 ] && echo "ok $cur" || echo "Already on it."; exit 0
fi

# a lock left behind by a killed switch must not block switching forever
if [ -d $LOCK ] && [ $(( $(date +%s) - $(stat -c %Y $LOCK 2>/dev/null || echo 0) )) -gt 60 ]; then rmdir $LOCK; fi
mkdir $LOCK 2>/dev/null || { [ $APP = 1 ] && echo locked || echo "A switch is already running."; exit 1; }
trap 'rmdir $LOCK' EXIT

if cam_busy; then
    [ $APP = 1 ] && { echo busy; exit 1; }
    echo ""; echo "A camera app has the camera open right now."
    echo "Close it (swipe it away from recents) and press Action again."; exit 1
fi
# the OnePlus camera can't run on the YAAP HAL; don't leave it in the background
[ $tgt = yaap ] && am force-stop $OPLUS

say "Switching to $(hal_name $tgt)... (camera is unavailable for ~6 s)"
s=$(awk '{print int($1)}' /proc/uptime)
hal_switch $tgt; r=$?
e=$(awk '{print int($1)}' /proc/uptime)
now=$(hal_cur)
[ $r = 0 ] && [ $now = $tgt ] && echo $tgt > $ST/hal_mode
log I "action(app=$APP): $cur -> $tgt, now $now, rc=$r, $((e-s))s"
desc_active
if [ $APP = 1 ]; then
    [ $now = $tgt ] && echo "ok $now" || { echo "fail $now"; exit 1; }
    exit 0
fi
echo ""
echo "Camera HAL: $(hal_name $now) ($((e-s)) s)"
cams_ready && echo "Cameras ready." || echo "Cameras not listed yet, give it a few seconds."
if [ $now = oos ]; then
    echo "OnePlus camera: ready to use. This stays after reboots."
else
    echo "OnePlus camera: don't open it on this HAL (it will close itself). This stays after reboots."
fi
