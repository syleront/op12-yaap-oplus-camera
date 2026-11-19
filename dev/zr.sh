L=/data/local/tmp/zr; rm -rf $L; mkdir -p $L
D=/data/adb/opc_live/libbinder.so; NS="nsenter -t 1 -m --"
cp /data/local/tmp/opc_push/libbinder.4m.so $D && chown 0:0 $D && chmod 644 $D && chcon u:object_r:system_lib_file:s0 $D || exit 1
$NS mount -o bind $D /system/lib64/libbinder.so || { echo bindfail; exit 1; }
$NS md5sum /system/lib64/libbinder.so | tee $L/md5.txt
echo "before: zyg=$(pidof zygote64) ss=$(pidof system_server)" | tee $L/pids.txt
/data/adb/ksu/bin/busybox setsid nohup logcat -b all -f $L/logcat.txt -r 16384 -n 3 >/dev/null 2>&1 &
/data/adb/ksu/bin/busybox setsid nohup sh /data/local/tmp/zr_watch.sh > $L/watch.txt 2>&1 &
sleep 1; echo restarting; setprop ctl.restart zygote
