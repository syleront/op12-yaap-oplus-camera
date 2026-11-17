# auto-rollback: if the framework isn't stable ~2 min after the restart, drop the patched libbinder and restart again
L=/data/local/tmp/zr; NS="nsenter -t 1 -m --"
sleep 95; a=$(pidof system_server); sleep 30; b=$(pidof system_server)
echo "$(date) ss@95s=$a ss@125s=$b boot=$(getprop sys.boot_completed)"
if [ -n "$a" ] && [ "$a" = "$b" ] && dumpsys activity -h >/dev/null 2>&1; then echo HEALTHY; exit 0; fi
echo "UNHEALTHY -> rollback"
$NS umount -l /system/lib64/libbinder.so; echo "umount rc=$?"
setprop ctl.restart zygote; echo "restarted stock"
