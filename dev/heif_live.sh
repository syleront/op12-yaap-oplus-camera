#!/system/bin/sh
# Live (non-persistent) test of the HEIC fix. Bind-mounts (init mount namespace):
#   patched libAPSClient-cmd-jni.so (DT_NEEDED libAPSClient-cmd-jni-extension.oplus.so) over the original
#   libheiffix.so over libAPSClient-cmd-jni-extension.oplus.so (not loaded by anything otherwise)
#   patched libAlgoProcess.so over /odm/lib64/libAlgoProcess.so (EXIF fix; running processes keep the old one)
# and restarts only the OnePlus camera app. Undo: "down", or any reboot.
#   sh heif_live.sh up | down | status
SRC=/data/local/tmp/heif
S=/data/adb/opc_live/heif
L=/system_ext/lib64
NS="nsenter -t 1 -m --"
MOUNTS="$S/libheiffix.so:$L/libAPSClient-cmd-jni-extension.oplus.so $S/cmdjni_live.so:$L/libAPSClient-cmd-jni.so $S/algo_live.so:/odm/lib64/libAlgoProcess.so"
mounted() { awk -v t=$1 '$5==t && $4 ~ /opc_live\/heif/' /proc/1/mountinfo | grep -q .; }
down() {
    for m in $MOUNTS; do t=${m#*:}; mounted $t && $NS umount -l $t; done
    am force-stop com.oplus.camera; rm -rf $S; echo down
}
case "$1" in
up)
    grep -q "opc_live/heif" /proc/1/mountinfo && { echo "already up"; exit 0; }
    rm -rf $S; mkdir -p $S; cp $SRC/cmdjni_live.so $SRC/libheiffix.so $SRC/algo_live.so $S/
    chown 0:0 $S/*; chmod 0644 $S/*
    chcon u:object_r:system_lib_file:s0 $S/libheiffix.so $S/cmdjni_live.so
    chcon $(ls -Z /odm/lib64/libAlgoProcess.so | awk '{print $1}') $S/algo_live.so
    for m in $MOUNTS; do $NS mount --bind ${m%%:*} ${m#*:} || { echo "FAIL ${m#*:}"; down; exit 1; }; done
    am force-stop com.oplus.camera; echo up ;;
down) down ;;
*) grep "opc_live/heif" /proc/1/mountinfo | awk '{print $4, $5}' ;;
esac
