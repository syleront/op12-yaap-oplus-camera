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
