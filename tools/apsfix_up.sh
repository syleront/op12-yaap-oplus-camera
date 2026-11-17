# Add libapsfix.so + patched libAlgoProcess.so into the live HAL overlay's /odm/lib64 layer
S=/data/adb/opc_live/hal/odm/lib64; NS="nsenter -t 1 -m --"; P=/data/local/tmp/opc_push
grep -q "lowerdir=$S:" /proc/1/mountinfo || { echo "hal overlay not up"; exit 1; }
[ -f $P/libAlgoProcess.so.orig ] || cp $S/libAlgoProcess.so $P/libAlgoProcess.so.orig
cp $P/libapsfix.so $P/libAlgoProcess.patched.so $S/ && mv $S/libAlgoProcess.patched.so $S/libAlgoProcess.so
chown 0:0 $S/libapsfix.so $S/libAlgoProcess.so; chmod 644 $S/libapsfix.so $S/libAlgoProcess.so
chcon $(ls -Z $P/libAlgoProcess.so.orig >/dev/null; ls -Z /odm/lib64/libAlgoProcess.so | awk '{print $1}') $S/libAlgoProcess.so $S/libapsfix.so
# remount so the overlay picks up the changed lower layer
$NS umount -l /odm/lib64 && $NS mount -t overlay -o "lowerdir=$S:/odm/lib64" overlay /odm/lib64 || echo "REMOUNT FAILED"
am force-stop com.oplus.camera
ls -lZ /odm/lib64/libapsfix.so /odm/lib64/libAlgoProcess.so; md5sum /odm/lib64/libAlgoProcess.so
grep -c "opc_live/hal/odm/lib64" /proc/1/mountinfo
