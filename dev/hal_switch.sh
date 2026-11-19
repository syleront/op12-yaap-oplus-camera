#!/system/bin/sh
# Switch the camera HAL between YAAP stock and the staged OnePlus (DerpFest OOS16) HAL.
#   sh hal_switch.sh oos | yaap | status
# The OnePlus files stay staged in $S; switching = overlay mount/umount + camera service restart.
S=/data/adb/opc_live/hal
NS="nsenter -t 1 -m --"
TGTS="/odm/lib64 /odm/etc /vendor/lib64 /vendor/etc"
LOCK=/dev/opc_hal_switch.lock

is_oos() { grep -q "lowerdir=$S/odm/lib64:" /proc/1/mountinfo; }
now_ms() { awk '{printf "%d", $1*1000}' /proc/uptime; }

stop_cam()  { stop cameraserver; stop vendor.camera-provider; }
start_cam() { start vendor.camera-provider; start cameraserver; }
wait_ready() {   # until cameraserver lists cameras again (max ~10 s)
    i=0; while [ $i -lt 50 ]; do
        n=$(dumpsys media.camera 2>/dev/null | grep -c "^== Camera HAL device.*static information")
        [ "${n:-0}" -ge 6 ] && return 0; sleep 0.2; i=$((i+1)); done; return 1
}

switch() {
    want=$1
    mkdir $LOCK 2>/dev/null || { echo "busy"; return 1; }
    t0=$(now_ms)
    if [ "$want" = oos ] && ! is_oos; then
        [ -d "$S/odm/lib64" ] || { echo "OnePlus HAL not staged"; rmdir $LOCK; return 1; }
        stop_cam
        for t in $TGTS; do [ -d "$S$t" ] && $NS mount -t overlay -o "lowerdir=$S$t:$t" overlay "$t"; done
        start_cam
    elif [ "$want" = yaap ] && is_oos; then
        stop_cam
        for t in $TGTS; do grep -q "lowerdir=$S$t:" /proc/1/mountinfo && $NS umount -l "$t"; done
        start_cam
    else
        echo "already $want"; rmdir $LOCK; return 0
    fi
    wait_ready && r=ready || r=TIMEOUT
    echo "switched to $want in $(( $(now_ms) - t0 )) ms ($r)"
    rmdir $LOCK
}

case "$1" in
    oos|yaap) switch "$1" ;;
    *) is_oos && echo "current: oos" || echo "current: yaap" ;;
esac
