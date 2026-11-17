#!/system/bin/sh
# Live (non-persistent) Stage C: add DerpFest's libOplusSecurity.so to /odm/lib64.
# The OPlus camera SDK needs it to decrypt /odm/etc/camera/config/oplus_camera_config;
# without it the vendor-tag config is empty and session setup breaks.
#   sh live_odm.sh up | down | status
SRC=/data/local/tmp/opc_push/odm
S=/data/adb/opc_live/odm
NS="nsenter -t 1 -m --"

status() { grep "opc_live/odm" /proc/1/mountinfo | awk '{print $5}'; ls -lZ /odm/lib64/libOplusSecurity.so 2>&1; }

up() {
    [ -f "$SRC/lib64/libOplusSecurity.so" ] || { echo "payload missing at $SRC"; exit 1; }
    if grep -q "opc_live/odm" /proc/1/mountinfo; then echo "already up"; status; exit 0; fi
    rm -rf "$S"; mkdir -p "$S"; cp -a "$SRC/." "$S/"
    chown -R 0:0 "$S"; chmod 0755 "$S" "$S/lib64"; chmod 0644 "$S"/lib64/*
    chcon u:object_r:vendor_file:s0 "$S" "$S/lib64"
    chcon u:object_r:same_process_hal_file:s0 "$S"/lib64/*
    $NS mount -t overlay -o "lowerdir=$S/lib64:/odm/lib64" overlay /odm/lib64 || { echo "FAIL overlay /odm/lib64"; exit 1; }
    status
}

down() {
    grep -q "opc_live/odm" /proc/1/mountinfo && $NS umount -l /odm/lib64
    rm -rf "$S"; status
}

case "$1" in up) up ;; down) down ;; *) status ;; esac
