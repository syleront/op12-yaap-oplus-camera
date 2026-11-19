# Development helpers

Scripts and probes used while porting. They are **not part of the module or the build**. Most of them
run as root on the phone, change the live system (bind mounts, service restarts) and refer to the
layout used during development (e.g. `payload/hal.tar`, staging dirs under `/data/adb`). Read a script
before running it, and only use it on a phone you can recover.

| file | what |
|---|---|
| `live_cs.sh`, `live_app.sh`, `live_hal.sh`, `live_odm.sh` | non-persistent live tests of the camera service, the app, and the HAL overlays |
| `zr.sh`, `zr_watch.sh` | live test of the patched libbinder (zygote restart with an auto-rollback watchdog) |
| `hal_switch.sh`, `hal_watch.sh` | early HAL switching / per-app auto-switching experiment (dropped) |
| `apsfix_up.sh` | live test of `libapsfix.so` + patched `libAlgoProcess.so` |
| `crashlog.sh`, `selinux_av_check.sh` | collect tombstones/logcat, list SELinux denials |
| `ocam_sepolicy.rule` | early SELinux rules for the app (the module uses `module/sepolicy.rule`) |
| `probe/` | small native probes (AHardwareBuffer planes, binder VM size, ...) |
