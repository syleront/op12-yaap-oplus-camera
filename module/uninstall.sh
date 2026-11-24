#!/system/bin/sh
# All mounts are per-boot only, so removing the module + reboot restores the stock ROM.
# (The OnePlus camera and gallery are system apps from the module; they disappear with it.)
rm -rf /data/adb/opcamera

# v1.x had a Camera HAL switch app (a normal app): remove it if still there, once the package
# manager is up (this script runs early in boot, before pm works).
nohup sh -c '
    i=0
    until [ "$(getprop sys.boot_completed)" = 1 ] || [ $i -ge 300 ]; do sleep 5; i=$((i+5)); done
    sleep 10
    pm path com.syleront.opcamera.halswitch >/dev/null 2>&1 && pm uninstall com.syleront.opcamera.halswitch
' >/dev/null 2>&1 &
