# OPlus camera on YAAP (OnePlus 12 / waffle) - KernelSU module work

Live-tested state (2026-11-17): OPlus camera (com.oplus.camera) fully working on YAAP-17
(CP2A.260605.016) with DerpFest's OOS16 (U.R4T3) camera HAL overlaid globally.

## Pieces
| Stage | What | Script |
|---|---|---|
| A | DerpFest cameraserver + libcameraservice + OOS libcsextimpl (+ src/shim/csext_shim.cpp) | tools/live_cs.sh |
| B | OplusCamera.apk + OplusPermissionDefiner (NO OplusAppPlatform: sharedUserId=android.uid.system bootloops) | tools/live_app.sh |
| C | DerpFest odm/vendor camera HAL files (payload/hal.tar, 44 files + libui-stock.so) | tools/live_hal.sh |
| - | sepolicy for priv_app_36 (payload/ocam_sepolicy.rule) | applied with ksud sepolicy patch |
| - | libbinder 4 MB binder VM | tools/zr.sh (+ zr_watch.sh auto-rollback) |

## Binary patches (reproducible)
### libAlgoProcess.so (DerpFest odm, md5 b706aa115dff69d3468c1ee61b24cd37)
YAAP's AOSP libnativewindow returns 1 plane from AHardwareBuffer_lockPlanes for QTI
P010_VENUS (0x7fa30c0a); DerpFest's framework special-cases it. APS then computes
scanline from a NULL UV pointer and crashes on capture.
- file off 241368: dynstr `AHardwareBuffer_lockPlanes` -> `AHardwareBuffer_lockPlaneX`
- file off 534952: NEEDED `libextendfile.so` -> `libapsfix.so\0\0\0\0`
- result md5 68fc7841b75b62d0369c7db90a9832e8
- src/apsfix/apsfix.c -> /odm/lib64/libapsfix.so (re-NEEDs libextendfile.so), adds Y/Cb/Cr planes
  with CbCr at rowStride * aligned_height (QTI handle ints[3]).

### libbinder.so (YAAP system, md5 56386724ce3384efdc99aec32aaa0536)
HAL's IOfflineCameraCallback result is ~1.87 MB > stock 1 MB binder VM -> "Binder buffer full",
captures time out (30 s) / get lost. DerpFest maps 4 MB.
- ProcessState mmap size: file off 0x9a5c8 `52a00208` (mov w8,#0x100000) -> `52a00808` (#0x400000)
- ProcessState munmap size: file off 0xa5b34 same change
- result md5 e0f824f911f8480639ec331a492b7b4d
Module must pattern-patch the device's libbinder (offsets change per YAAP build) and skip if
the pattern is not found.

## Gotchas
- KernelSU live sepolicy patches don't bump selinux status `policyload`, so userspace AVCs
  (servicemanager) keep cached denials. Live fix: dd /sys/fs/selinux/policy -> /sys/fs/selinux/load
  (single write). Not an issue at boot.
- adb `su -c "a; b"` only runs `a` as root: push scripts and run them.
- Never restart zygote / reboot without the user's OK; always keep an auto-rollback.

## Known issues
- Slow-mo: HAL runs HFR at ~60 fps instead of 240 -> viewfinder 7.5 fps (1 of 8 batch frames).
- OOS HAL globally drops YAAP's third-party camera improvements -> trying per-app HAL switching.

## KernelSU module (module/, tools/build_module.sh -> build/opcamera_yaap-<ver>.zip)
- No system/ dir: KSU 3.x has no metamodule here, and we want our own boot guard. post-fs-data.sh mounts
  everything in init's ns (overlays from /data/adb/modules/opcamera_yaap/files/{sys,hal}, cameraserver
  bind+suid, libbinder bind from /data/adb/opcamera/libbinder.so).
- libbinder is patched on-device at boot by bin/binderpatch (src/binderpatch) from the ROM's own lib,
  cached by source md5 -> re-done automatically after YAAP updates; skipped if pattern not found.
- Boot guard: /data/adb/opcamera/boot_pending set at post-fs-data, cleared by service.sh after
  boot_completed + system_server stable 20 s. Still present next boot -> module disables itself.
  No boot_completed within 300 s -> service.sh disables module and reboots.
- HAL mode (oos|yaap) in /data/adb/opcamera/hal_mode; Action button = live switch (refuses while a camera is open).
- Lens-row fix: src/zoomfix RRO (dimen zoom_arc_seekbar_focus_circle_center_y 90dp -> 171dp), preinstalled
  in /product/overlay (user-installed RROs need the target's cert). Non-static, enabled by service.sh unless
  The overlay value must be in values-sw380dp (target defines sw363dp-2772x1272; an RRO entry only wins if its config is >= as specific), link with --no-resource-deduping.
  /data/adb/opcamera/zoomfix = off. Cause: am.w.z4 sagitta term r - sqrt(r^2 - (W/2)^2) with r = 199dp = 697px
  < 720 = W/2 -> NaN -> row ~280 px too high at 1440 px width.
- Labels come from the live-tested staging (tools/gen/labels.txt); build refuses unlabeled files and APKs with sharedUserId.
