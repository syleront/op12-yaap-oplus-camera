# OnePlus Camera for YAAP (OnePlus 12)

A root module (KernelSU, Magisk, APatch) that brings the OnePlus (OxygenOS) camera and gallery to
**YAAP on the OnePlus 12 (waffle)**. The camera runs on **YAAP's own camera HAL** (YAAP ships OnePlus's
camera HAL). The camera app and its camera service come from DerpFest's OnePlus camera port.
Nothing is written to system partitions: everything is mounted at boot from the module, so removing it
and rebooting gives you stock YAAP back.

> **Please don't contact the YAAP, LineageOS or DerpFest maintainers about this module.** It's an unofficial
> third-party mod, and they don't support it. Post questions and bug reports in the comments under
> the module's post instead. Also, if something breaks while the module is installed, remove it and
> check again before reporting a bug to your ROM.

## Requirements
- OnePlus 12 (waffle) on **YAAP, Android 17**. Tested on YAAP `17-Calypso-waffle-20261116` (Android build
  `CP2A.260605.016`). The installer refuses other devices, other Android versions and stock OxygenOS/ColorOS.
- **Experimental:** other custom ROMs on the OnePlus 12 (LineageOS, crDroid, ...), Android 17, as long as
  they use OnePlus's camera HAL like YAAP does (otherwise the module stays off). Not tested yet; the boot
  guard below still applies.
- **KernelSU** (or a fork). **Experimental:** Magisk or APatch.

## What you get
- **OnePlus Camera** on the ROM's camera HAL: all lenses, modes and OnePlus processing. Hidden because they
  don't work properly on YAAP: the **Hi-Res** mode (only worked at 1x), the **Pro video** mode (green in low
  light) and Video mode's **HDR (Dolby Vision)** switch (never recorded; at 60 fps it froze the camera). For
  full-resolution photos on all three lenses, use another camera app (e.g. Photon Camera).
- **OnePlus Photos** (gallery), including the photo editor.
- Other camera apps keep working as before, on the same HAL (no switching needed).
  The OnePlus camera sees the sensors' 12 MP (binned) sizes, like on OxygenOS; other apps still see the 50 MP ones.

## Install
1. Root manager (KernelSU / Magisk / APatch) → Modules → Install from storage → `opcamera_yaap-<version>.zip`.
2. Reboot.

**Updating from v1.x:** install v2 over it and reboot (no need to remove v1 first). v2 no longer
ships DerpFest's OnePlus camera HAL, so the Camera HAL switch (Action button, tile, icon) is gone. The
installer removes the switch app.

## If the phone doesn't boot
You don't need to do anything special. The module checks whether the boot finished:
- If the phone hasn't finished booting after ~5 minutes, the module **disables itself and reboots**.
- Or force a reboot: hold **Power + Volume Up + Volume Down** together until the phone restarts.
  If the previous boot never finished, the module disables itself and mounts nothing.

Then remove it in your root manager, or re-enable it after fixing whatever caused it.

## Uninstall
Remove the module in your root manager and reboot. The camera and gallery go away with it.

## Known issues
- **60 fps video:** the viewfinder looks greyish; the recorded video is fine.
- **Slow motion:** the viewfinder lags (a YAAP platform limit; the same with any camera app).
- **Photo aspect ratio 65:24** isn't available (YAAP's HAL can't do it); 1:1, 4:3, 16:9 and Full work.
- **XPAN mode:** with a filter (anything other than "Original") the saved photo is plain green. In low light
  it's green also without a filter.
- **Gallery:** downloadable editor plugins / AI models don't download (they need OnePlus system services
  that neither YAAP nor DerpFest have). Built-in editing works.
- The camera HAL can occasionally crash; it restarts on its own (reopen the camera).
- **After a YAAP update** the camera may stop working, because the module uses DerpFest's camera service.
  The ROM's camera libraries that the module adjusts (see below) are redone automatically. If the camera
  breaks, disable the module and report it.

## What it changes (while enabled)
- Mounts DerpFest's camera service and the OnePlus camera/gallery apps and their libraries over `/system`,
  `/system_ext` and `/product`. The camera service is patched so that:
  - the OnePlus camera takes the camera from other apps instead of sharing it;
  - the OnePlus camera sees binned sensor sizes;
  - portrait mode doesn't crash it.

  The camera app is patched to hide the Hi-Res and Pro video modes and Video mode's HDR switch. Its unit SDK
  (`com.oplus.camera.unit.sdk.jar`) is patched so that Hi-Res mode asks the HAL for sizes it accepts.
- Adds what the OnePlus camera needs on top of the ROM's camera HAL, over `/odm` and `/vendor`:
  - `libOplusSecurity.so`;
  - the camera app's processing libraries (patched for YAAP), licences and configs;
  - OnePlus's `libui`, as `libus.so`.
- Fixes 9 of the ROM's OnePlus camera HAL libraries. They were built against OnePlus's `libui`; with AOSP's
  `libui` the camera HAL corrupts its memory as soon as the OnePlus camera uses them. At boot the module
  makes copies that load `libus.so` instead (one name changed, made on the phone from your ROM's own files)
  and mounts them over the originals.
- Uses a copy of the ROM's camera app config (`/odm/etc/camera/config/camera_unit_config`) with photo-mode
  preview sizes that YAAP's HAL supports, and the 65:24 ratio hidden. Made on the phone at boot from your
  ROM's own file.
- Uses a copy of the ROM's camera HAL config (`/odm/etc/camera/CameraHWConfiguration.config`) with the video
  low-light mode off (1 line changed; 30 fps video flashed green in low light). Made on the phone at boot
  from your ROM's own file.
- Uses a copy of YAAP's `libbinder` with a 4 MB binder buffer instead of 1 MB (the camera sends large
  results). It is generated on the phone from your ROM's own file.
- Adds SELinux rules for the camera service and privileged apps (needed by the OnePlus camera and gallery).
- Sets a few props so the camera recognizes the device (market name "OnePlus 12", etc.).

## Reporting problems
Post in the comments under the module's post (not in YAAP or DerpFest chats). Please include:
- `/data/adb/opcamera/log.txt` (the module's Action button shows its status and the last lines)
- your ROM and build (Settings → About phone)
- what you did and what happened (a logcat if you can)

## Extras
- Lens row / zoom ring position fix: on by default. To turn it off:
  `echo off > /data/adb/opcamera/zoomfix` (as root), then reboot.

## Building from source
This repository contains only the module's own code and scripts. No OnePlus or DerpFest files are
included: you extract them from the DerpFest ROM yourself. See [docs/BUILDING.md](docs/BUILDING.md);
[docs/PAYLOAD.md](docs/PAYLOAD.md) lists where every shipped file comes from and how it's patched.

| path | what |
|---|---|
| `module/` | the module scripts (install, mounts, boot guard, status action) |
| `files/` | small config files the module adds (permissions, sysconfig) |
| `src/` | our native code (`apscrop`, `apsfix`, `binderpatch`, `csfix`, `evictfix`, `heiffix`, `relink`, `shim`) and the `zoomfix` overlay; `halswitch` is v1.x only and no longer built |
| `tools/` | build scripts, payload extraction, binary patchers |
| `payload/` | extracted DerpFest files (not in git); `MANIFEST.sha256` pins the tested versions |
| `docs/` | build and payload docs, technical notes |
| `dev/` | live-test scripts and probes used during development (not part of the build) |

## Credits
- **DerpFest** (OnePlus 12 maintainers): the OnePlus camera port this module is based on.
- **YAAP** team.
- OnePlus / OPLUS: camera, gallery and HAL (proprietary, all rights theirs).

## Disclaimer
Use at your own risk. Not affiliated with OnePlus, YAAP, LineageOS or DerpFest, and not supported by them: don't
ask their maintainers or chats for help with it.
