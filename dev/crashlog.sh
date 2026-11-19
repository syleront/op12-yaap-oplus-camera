#!/system/bin/sh
# Crash-resilient logging: logcat + dmesg to /data, fsync'd every 0.5 s.
# Stop with: touch /data/local/tmp/opc_log.stop
D=/data/local/tmp
rm -f $D/opc_log.stop $D/opc_lc.txt $D/opc_dm.txt
logcat -b all -v threadtime -f $D/opc_lc.txt &
LC=$!
dmesg -w > $D/opc_dm.txt &
DM=$!
while [ ! -f $D/opc_log.stop ]; do sync; sleep 0.5; done
kill $LC $DM 2>/dev/null
sync
