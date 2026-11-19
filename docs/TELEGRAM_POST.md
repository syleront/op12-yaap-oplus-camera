📸 **OnePlus Camera for YAAP — OnePlus 12 (waffle)**
KernelSU module · v1.0.1

OnePlus camera + OnePlus Photos on YAAP, based on DerpFest's port. Nothing is written to system partitions: remove the module, reboot, and you're back on stock YAAP.

**Features**
• OnePlus camera with the OnePlus camera HAL (all lenses, modes, processing)
• OnePlus Photos (gallery) with the editor
• Switch back to YAAP's camera HAL without rebooting: KernelSU Action button, quick settings tile or home-screen icon ("Camera HAL")

**Requirements**
• OnePlus 12 on YAAP Android 17 (tested: CP2A.260605.016)
• KernelSU

**Install**
1. KernelSU → Modules → install the zip, reboot
2. KernelSU → Superuser → allow root for "Camera HAL"
3. Optional: add the "Camera HAL" tile to quick settings

**Notes**
• OnePlus HAL (default): OnePlus camera works. YAAP HAL: OnePlus camera won't open; use it if another camera app misbehaves. Close camera apps before switching. The choice is kept after reboot.
• Bootloop protection: if boot doesn't finish, the module disables itself (automatically after ~5 min, or force a reboot by holding Power + Vol Up + Vol Down together).

**Known issues**
• 60 fps: greyish viewfinder (the video itself is fine)
• Slow-mo viewfinder lags
• Shooting right after switching lenses can lose the photo (stuck on "processing"); wait ~1–2 s after switching. Same on DerpFest
• Gallery plugin / AI model downloads don't work
• After a YAAP update the camera may break: disable the module and report

⚠️ **Unofficial mod.** Please don't contact the YAAP or DerpFest maintainers or chats about it. They don't support it. Ask everything about the module in the comments below. If something breaks with the module installed, remove it and check again before reporting a bug to YAAP.

**Bug reports (in the comments):** send /data/adb/opcamera/log.txt, your YAAP build and what happened.

Credits: DerpFest OnePlus 12 maintainers, YAAP team. OnePlus camera/gallery/HAL © OnePlus. Use at your own risk.
