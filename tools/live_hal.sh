#!/system/bin/sh
# Live (non-persistent) test: DerpFest's camera HAL blobs (camx + odm OPlus camera stack)
# layered over YAAP's /odm/lib64, /odm/etc, /vendor/lib64, /vendor/etc.
# Only camera files are in the layer; GPU driver and generic vendor libs stay YAAP's.
# Nothing survives a reboot.   sh live_hal.sh up | down | status
SRC=/data/local/tmp/opc_push/hal.tar
S=/data/adb/opc_live/hal
NS="nsenter -t 1 -m --"
TGTS="/odm/lib64 /odm/etc /vendor/lib64 /vendor/etc"

status() {
    grep "opc_live/hal" /proc/1/mountinfo | awk '{print $5}'
    echo "provider: $(pidof vendor.qti.camera.provider-service_64)  cameraserver: $(pidof cameraserver)"
}

restart_cam() {
    stop cameraserver; stop vendor.camera-provider; sleep 1
    start vendor.camera-provider; sleep 2; start cameraserver; sleep 3
}

up() {
    [ -f "$SRC" ] || { echo "payload missing at $SRC"; exit 1; }
    if grep -q "opc_live/hal" /proc/1/mountinfo; then echo "already up"; status; exit 0; fi
    # the single-file odm overlay from live_odm.sh is superseded by this layer
    grep -q "opc_live/odm" /proc/1/mountinfo && $NS umount -l /odm/lib64
    rm -rf "$S"; mkdir -p "$S"; tar -xf "$SRC" -C "$S" || { echo "untar failed"; exit 1; }
    chown -R 0:0 "$S"
    find "$S" -type d -exec chmod 0755 {} \;
    find "$S" -type f -exec chmod 0644 {} \;
    # copy SELinux labels from the real path; new files get their parent's label
    find "$S" -mindepth 1 | while read p; do
        real=${p#$S}
        if [ -e "$real" ]; then lbl=$(ls -dZ "$real" | awk '{print $1}')
        else lbl=$(ls -dZ "$(dirname "$real")" | awk '{print $1}'); fi
        chcon "$lbl" "$p"
    done
    chcon u:object_r:same_process_hal_file:s0 "$S/odm/lib64/libOplusSecurity.so"
    for t in $TGTS; do
        [ -d "$S$t" ] || continue
        $NS mount -t overlay -o "lowerdir=$S$t:$t" overlay "$t" && echo "overlay ok: $t" || { echo "FAIL: $t"; down; exit 1; }
    done
    restart_cam
    status
}

down() {
    for t in $TGTS; do grep -q "lowerdir=$S$t:" /proc/1/mountinfo && $NS umount -l "$t"; done
    restart_cam
    rm -rf "$S"
    status
}

case "$1" in up) up ;; down) down ;; *) status ;; esac
