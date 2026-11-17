#!/system/bin/sh
# Runs early in boot, before zygote and the camera HAL start. Mounts everything (nothing persists:
# a reboot with the module disabled is always a clean YAAP).
MODDIR=${0%/*}
. $MODDIR/common.sh
mkdir -p $ST; trim_log
rm -f $ACTIVE
log I "---- boot: $(getprop ro.build.fingerprint)"

if ! reason=$(preflight); then
    log W "skipped: $reason"; set_desc "Inactive: $reason. Nothing was mounted."; exit 0
fi

# Boot-loop guard: boot_pending is removed by service.sh once the system has booted and is stable.
# If it is still here, the last boot with our mounts never got there -> stay off.
if [ -f $ST/boot_pending ]; then
    rm -f $ST/boot_pending; touch $MODDIR/disable
    log E "previous boot did not complete -> module disabled, nothing mounted"
    set_desc "DISABLED: the previous boot did not complete, so nothing was mounted. Re-enable to try again (log: $LOG)."
    exit 0
fi

fp=$(getprop ro.build.fingerprint)
if [ "$(cat $ST/fingerprint 2>/dev/null)" != "$fp" ]; then
    log I "ROM build changed: $(cat $ST/fingerprint 2>/dev/null) -> $fp"; echo "$fp" > $ST/fingerprint
fi

labels_ok || { log W "labels missing, re-applying"; apply_labels; }

touch $ST/boot_pending; sync

binder_prepare && use_binder=1 || log W "libbinder 4 MB patch not available; big captures may be slow"

if ! mount_sys; then
    umount_all; rm -f $ST/boot_pending
    set_desc "Inactive: mounting failed, nothing left mounted (log: $LOG)."; exit 0
fi
if [ -n "$use_binder" ]; then
    $NS mount -o bind $ST/libbinder.so /system/lib64/libbinder.so || log E "libbinder bind failed"
fi

v=$(getprop oplus.software.camera.10bit); [ -n "$v" ] && echo "$v" > $ST/10bit.orig
if [ "$(hal_mode)" = oos ]; then hal_up || log E "OnePlus HAL mount failed, staying on YAAP HAL"; fi

set_props
touch $ACTIVE
desc_active
log I "mounted: sys binder=${use_binder:-0} hal=$(hal_cur)"
