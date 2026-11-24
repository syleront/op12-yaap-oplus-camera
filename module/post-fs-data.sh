#!/system/bin/sh
# Runs early in boot, before zygote and the camera HAL start. Mounts everything (nothing persists:
# a reboot with the module disabled is always the clean ROM).
MODDIR=${0%/*}
. $MODDIR/common.sh
mkdir -p $ST; trim_log
rm -f $ACTIVE
log I "---- boot: $(getprop ro.build.fingerprint)"

if ! reason=$(preflight); then
    log W "skipped: $reason ($(rom_info))"; set_desc "Inactive: $reason. Nothing was mounted."; exit 0
fi

# Boot-loop guard: boot_pending is removed by service.sh once the system has booted and is stable.
# If it is still here, the last boot with our mounts never got there -> stay off.
if [ -f $ST/boot_pending ]; then
    rm -f $ST/boot_pending; touch $MODDIR/disable
    log E "previous boot did not complete -> module disabled, nothing mounted"
    set_desc "DISABLED: the previous boot did not complete, so nothing was mounted. Re-enable to try again (log: $LOG)."
    exit 0
fi

[ "$(rom_id)" = yaap ] || log I "ROM: $(rom_name) (experimental): $(rom_info) provider=$(cam_provider)"

fp=$(getprop ro.build.fingerprint)
if [ "$(cat $ST/fingerprint 2>/dev/null)" != "$fp" ]; then
    log I "ROM build changed: $(cat $ST/fingerprint 2>/dev/null) -> $fp"; echo "$fp" > $ST/fingerprint
fi

if [ -f $IMG ]; then
    img_mount || { set_desc "Inactive: could not mount the module's image, nothing was mounted (log: $LOG)."; exit 0; }
    labels_ok || { log E "labels missing in the image"; set_desc "Inactive: the module's image is damaged, reinstall it."; exit 0; }
else
    labels_ok || { log W "labels missing, re-applying"; apply_labels; }
fi

touch $ST/boot_pending; sync

binder_prepare && use_binder=1 || log W "libbinder 4 MB patch not available; big captures may be slow"
relink_prepare || { rm -f $ST/boot_pending
    set_desc "Inactive: the ROM's camera libraries could not be prepared, nothing was mounted (log: $LOG)."; exit 0; }
unitcfg_prepare || { rm -f $UCF $UCF.key; log W "camera config not prepared; some photo ratios won't work"; }
hwcfg_prepare || { rm -f $HCF $HCF.key; log W "HAL config not prepared; 30 fps video may flash green in low light (Video mode)"; }

if ! mount_sys; then
    umount_all; rm -f $ST/boot_pending
    set_desc "Inactive: mounting failed, nothing left mounted (log: $LOG)."; exit 0
fi
if [ -n "$use_binder" ]; then
    $NS mount -o bind $ST/libbinder.so /system/lib64/libbinder.so || log E "libbinder bind failed"
fi

# the OnePlus camera's additions to the ROM's camera HAL; without them it would crash the HAL
if ! hal_up; then
    umount_all; rm -f $ST/boot_pending
    set_desc "Inactive: mounting the camera HAL files failed, nothing left mounted (log: $LOG)."; exit 0
fi

set_props
touch $ACTIVE
desc_active
log I "mounted: sys binder=${use_binder:-0} hal relinks=$(find $RL -type f 2>/dev/null | wc -l) unitcfg=$(unitcfg_mounted && echo 1 || echo 0) hwcfg=$(hwcfg_mounted && echo 1 || echo 0)"
