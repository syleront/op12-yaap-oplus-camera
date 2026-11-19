# OnePlus Camera for YAAP (OnePlus 12)

A KernelSU module that brings the OnePlus (OxygenOS) camera and gallery to **YAAP on the OnePlus 12
(waffle)**, using the OnePlus camera port from DerpFest. Nothing is written to system partitions:
everything is mounted at boot from the module, so removing it and rebooting gives you stock YAAP back.

> **Please don't contact the YAAP or DerpFest maintainers about this module.** It's an unofficial
> third-party mod, and they don't support it. Post questions and bug reports in the comments under
> the module's post instead. Also, if something breaks while the module is installed, remove it and
> check again before reporting a bug to YAAP.

## Requirements
- OnePlus 12 (waffle) on **YAAP, Android 17**. Tested on YAAP `17-Calypso-waffle-20261001` and
  `20261116` (Android build `CP2A.260605.016`). The installer
  refuses other ROMs/devices.
- **KernelSU** (the installer refuses Magisk/APatch).

## What you get
- **OnePlus Camera** with the OnePlus camera HAL (all lenses, modes and processing).
- **OnePlus Photos** (gallery), including the photo editor.
- A **Camera HAL switch**: go back to YAAP's own camera HAL at any time without rebooting, from
  - the module's **Action** button in KernelSU,
  - a **"Camera HAL" quick settings tile**,
  - a **"Camera HAL" home-screen icon**.

## Install
1. KernelSU → Modules → Install from storage → `opcamera_yaap-<version>.zip`.
2. Reboot.
3. KernelSU → Superuser → allow root for **Camera HAL** (needed by the tile and icon).
4. Optional: edit quick settings and add the **Camera HAL** tile.

## The two camera HALs
| HAL | OnePlus camera | Notes |
|---|---|---|
| **OnePlus** (default) | works | tile on, subtitle "OnePlus" |
| **YAAP** (stock) | **won't open** | tile off, subtitle "YAAP"; use it if another camera app misbehaves |

- Switching takes ~5–20 s; close every camera app first (the switch refuses while a camera is open).
- The HAL you pick is kept after a reboot.

## If the phone doesn't boot
You don't need to do anything special. The module checks whether the boot finished:
- If the phone hasn't finished booting after ~5 minutes, the module **disables itself and reboots**.
- Or force a reboot: hold **Power + Volume Up + Volume Down** together until the phone restarts.
  If the previous boot never finished, the module disables itself and mounts nothing.

Then remove it in KernelSU, or re-enable it after fixing whatever caused it.

## Uninstall
Remove the module in KernelSU and reboot. The camera, gallery and Camera HAL app all go away with it.

## Known issues
- **60 fps video:** the viewfinder looks greyish; the recorded video is fine.
- **Slow motion:** the viewfinder lags.
- **Gallery:** downloadable editor plugins / AI models don't download (they need OnePlus system services
  that neither YAAP nor DerpFest have). Built-in editing works.
- **Photo lost right after switching lenses:** if you shoot within ~1–2 s of switching lenses (e.g. 0.6× → 1×),
  the OnePlus HAL can fail the capture: the photo isn't saved and its thumbnail stays on "processing". Wait a
  moment after switching before shooting. DerpFest has the same issue (it's in the OnePlus HAL/camera).
- **YAAP HAL mode:** the OnePlus camera doesn't open. Switch to the OnePlus HAL first.
- The camera HAL can occasionally crash; it restarts on its own (reopen the camera).
- **After a YAAP update** the camera may stop working: the module keeps using DerpFest's camera service
  in both HAL modes. If that happens, disable the module and report it.

## What it changes (while enabled)
- Mounts DerpFest's camera service (patched so the OnePlus camera takes the camera from other apps instead
  of sharing it, which crashes the OnePlus HAL), OnePlus camera/gallery apps and their libraries over `/system`,
  `/system_ext` and `/product`; in OnePlus HAL mode also the OnePlus camera HAL over `/odm` and `/vendor`.
- Uses a copy of YAAP's `libbinder` with a 4 MB binder buffer instead of 1 MB (the OnePlus HAL sends
  large results). It is generated on the phone from your ROM's own file.
- Adds SELinux rules for the camera service and privileged apps (needed by the OnePlus camera and gallery).
- Sets a few props so the camera recognizes the device (market name "OnePlus 12", etc.).

## Reporting problems
Post in the comments under the module's post (not in YAAP or DerpFest chats). Please include:
- `/data/adb/opcamera/log.txt`
- your YAAP build (Settings → About phone)
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
| `module/` | the KernelSU module scripts (install, mounts, boot guard, HAL switch) |
| `files/` | small config files the module adds (permissions, sysconfig) |
| `src/` | our native code (`apsfix`, `binderpatch`, `evictfix`, `heiffix`, `shim`) and APKs (`halswitch`, `zoomfix`) |
| `tools/` | build scripts, payload extraction, binary patchers |
| `payload/` | extracted DerpFest files (not in git); `MANIFEST.sha256` pins the tested versions |
| `docs/` | build and payload docs, technical notes |
| `dev/` | live-test scripts and probes used during development (not part of the build) |

## Credits
- **DerpFest** (OnePlus 12 maintainers): the OnePlus camera port this module is based on.
- **YAAP** team.
- OnePlus / OPLUS: camera, gallery and HAL (proprietary, all rights theirs).

## Disclaimer
Use at your own risk. Not affiliated with OnePlus, YAAP or DerpFest, and not supported by them: don't
ask their maintainers or chats for help with it.
