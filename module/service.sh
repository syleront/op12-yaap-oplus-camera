#!/system/bin/sh
# Boot-loop guard, second half. Clears boot_pending once Android has booted and system_server
# is stable. If Android never finishes booting, disable the module and reboot into clean YAAP.
MODDIR=${0%/*}
. $MODDIR/common.sh
[ -f $ACTIVE ] || exit 0

t=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 5; t=$((t+5))
    if [ $t -ge 300 ]; then
        log E "boot did not complete in 300 s -> disabling module and rebooting"
        touch $MODDIR/disable; rm -f $ST/boot_pending
        set_desc "DISABLED: Android did not finish booting with this module, it rebooted without it (log: $LOG)."
        sync; sleep 1; reboot
        exit 0
    fi
done
log I "boot completed after ~${t}s"

# system_server must stay up (same pid) for 20 s in a row; give it up to 10 min
t=0; ss=$(pidof system_server)
while [ $t -lt 600 ]; do
    sleep 20; t=$((t+20)); now=$(pidof system_server)
    if [ -n "$now" ] && [ "$now" = "$ss" ]; then
        rm -f $ST/boot_pending
        log I "system stable, boot guard cleared"
        cams_ready || log W "camera service lists fewer than 6 cameras after boot"
        zoomfix_apply
        exit 0
    fi
    log W "system_server restarted ($ss -> $now)"; ss=$now
done
log E "system_server kept restarting; module will stay off on next boot"
