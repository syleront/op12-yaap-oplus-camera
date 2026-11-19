#!/system/bin/sh
# Live (non-persistent) test of the DerpFest cameraserver stack on YAAP.
# Nothing here survives a reboot. Usage (as root):
#   sh live_cs.sh up      # stage + mount + restart cameraserver
#   sh live_cs.sh down    # unmount + restart stock cameraserver
#   sh live_cs.sh status
# Expects the payload pushed to /data/local/tmp/opc_push/cameraserver/{system,system_ext}

SRC=/data/local/tmp/opc_push/cameraserver
S=/data/adb/opc_live/cameraserver
NS="nsenter -t 1 -m --"

is_mounted() { grep -q " $1 " /proc/1/mountinfo; }

status() {
    echo "--- mounts (init ns)"
    grep -E "opc_live" /proc/1/mountinfo | awk '{print $5, $NF}'
    echo "--- cameraserver pid: $(pidof cameraserver)"
    ls -l /proc/$(pidof cameraserver)/exe 2>/dev/null
    grep -c "libcsextimpl\|libcameraservice.so" /proc/$(pidof cameraserver)/maps 2>/dev/null | sed 's/^/ext libs mapped (lines): /'
}

up() {
    [ -d "$SRC/system" ] || { echo "payload missing at $SRC"; exit 1; }
    if grep -q opc_live /proc/1/mountinfo; then echo "already up"; status; exit 0; fi
    rm -rf "$S"; mkdir -p "$S"
    cp -a "$SRC/." "$S/"
    chown -R 0:0 "$S"
    chmod 0755 "$S/system/bin/cameraserver"
    find "$S" -type d -exec chmod 0755 {} \;
    find "$S" -name '*.so' -exec chmod 0644 {} \;
    chcon -R u:object_r:system_lib_file:s0 "$S/system/lib64" "$S/system_ext/lib64"
    chcon u:object_r:cameraserver_exec:s0 "$S/system/bin/cameraserver"

    $NS mount -t overlay -o "lowerdir=$S/system/lib64:/system/lib64" overlay /system/lib64 || { echo "FAIL overlay system/lib64"; exit 1; }
    $NS mount -t overlay -o "lowerdir=$S/system_ext/lib64:/system_ext/lib64" overlay /system_ext/lib64 || { echo "FAIL overlay system_ext/lib64"; down; exit 1; }
    $NS mount -o bind "$S/system/bin/cameraserver" /system/bin/cameraserver || { echo "FAIL bind cameraserver"; down; exit 1; }
    # /data is nosuid; a bind inherits that and SELinux then refuses the init->cameraserver transition
    $NS mount -o remount,bind,suid /system/bin/cameraserver || { echo "FAIL remount suid"; down; exit 1; }
    /data/adb/ksud sepolicy patch "allow cameraserver vendor_default_prop file { read open getattr map }" >/dev/null
    /data/adb/ksud sepolicy patch "allow cameraserver vendor_file file { read open getattr map execute }" >/dev/null
    ls -Z /system/bin/cameraserver /system/lib64/libcameraservice.so /system_ext/lib64/libcsextimpl.so

    stop cameraserver; sleep 1; start cameraserver; sleep 3
    status
}

down() {
    stop cameraserver
    $NS umount /system/bin/cameraserver 2>/dev/null
    $NS umount /system_ext/lib64 2>/dev/null
    $NS umount /system/lib64 2>/dev/null
    start cameraserver; sleep 2
    rm -rf /data/adb/opc_live
    status
}

case "$1" in
    up) up ;;
    down) down ;;
    *) status ;;
esac
