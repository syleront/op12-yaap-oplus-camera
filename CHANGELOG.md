# Changelog

Versions are `vMAJOR.MINOR.PATCH`: PATCH = fixes, MINOR = new features, MAJOR = breaking changes
(e.g. dropping support for an older YAAP). `versionCode` = MAJOR×10000 + MINOR×100 + PATCH.

## v2.0.5
- The Hi-Res and Pro video modes are hidden: Hi-Res only worked at 1x and Pro video turned green in low
  light. For full-resolution photos on all lenses, use another camera app (e.g. Photon Camera).
- Video mode's HDR (Dolby Vision) switch is hidden. It never recorded on YAAP, and at 60 fps turning it on
  froze Video mode (black viewfinder, no buttons), so it couldn't be turned off again. If it was on, Video
  mode works again after the update. HDR video in other camera apps isn't affected.
- The camera app is signed with a new key (the old one was lost). Android 17 keeps a system app's data when
  its key changes, so the camera's settings stay as they were.

## v2.0.4
- Fixed: Pro video had a colour tint in normal light (since v2.0.3). v2.0.3's Pro video change is undone:
  it didn't fix the green picture in low light either. Only the video low-light mode is still off (1 line
  of the HAL's config), which fixes Video mode at 30 fps.
- Known issues added: Pro video turns green in low light (use Video mode there), XPAN is green in low light
  also without a filter, and Dolby Vision doesn't record on YAAP (leave it off).

## v2.0.3
- Fixed: changing the photo aspect ratio to 1:1, 16:9 or Full froze the camera, and 65:24 left it black
  (also after reopening it). The camera asked YAAP's HAL for preview sizes it doesn't have. The module now
  gives the camera sizes the HAL supports (same ratios). 65:24 is hidden: the HAL can't do it. If the camera
  was stuck on 65:24, it opens normally again (back to 4:3) the second time you open it.
- Fixed: the camera app could crash when leaving it (Home, opening the gallery, switching apps): the
  cleanup of the text-enhancement step used an engine that was never created or already freed.
- Fixed: video at 30 fps (Video and Pro video) flashed green in low light, in the viewfinder and in
  recordings. Two of YAAP's HAL processing paths output frames without colour there: the video low-light
  mode (now off) and, in Pro video, staggered HDR (now off in Pro video only). The module uses a copy of
  the HAL's config with these 3 lines changed, made at boot. 60 fps wasn't affected.
- Fixed: in Pro video (and Master mode), the manual controls' labels (ISO, S, EV...) sat under the lens
  buttons (0.6 / 1x / 3). The controls are now a bit lower (12 dp); the lens row stays where it was.

## v2.0.2
- Fixed: Text mode crashed the camera. YAAP's copy of the OCR library (`libYTCommon.so`) can't be
  loaded, so the module ships DerpFest's (same code, laid out correctly).
- Fixed: Hi-Res mode hung the camera at 1x. It now takes 50 MP (8192x6144) photos. At 0.6x and 3x,
  Hi-Res still doesn't work (see Known issues).

## v2.0.1
- Fixed: v2.0.0 stayed inactive ("the ROM's camera libraries could not be prepared"). Reading the
  SELinux label of the ROM's libraries failed under the root manager's busybox.

## v2.0.0
The OnePlus camera now runs on YAAP's own camera HAL. DerpFest's OnePlus camera HAL is no longer shipped.
- No HAL switch any more (Action button mode, quick settings tile, home-screen icon). Other camera apps
  work on the same HAL as the OnePlus camera. Installing over v1.x removes the switch app.
- Some of the ROM's OnePlus camera HAL libraries were built against OnePlus's libui. At boot the module now
  relinks them on the phone (`bin/relink`) to load that libui, which it ships as `libus.so`. This is redone
  automatically after ROM updates.
- The OnePlus camera sees the sensors' binned (12 MP) sizes; other apps keep the 50 MP ones (camera service hook).
- Fixed on the ROM's HAL:
  - Portrait mode: the camera service crashed on empty physical-camera results.
  - Zoomed (3x/6x) low-light and night photos: offline processing used its crop in the wrong
    coordinates, which gave a 2x crop of the top-left corner.
- The module stays off on ROMs that don't use OnePlus's camera HAL (no `camera.oemlayer.so`).
- The Action button shows the module's status and the end of its log.
- Smaller download (~290 MB instead of ~320 MB).

## v1.2.1
- Image fallback (kernels that refuse /data in overlays): if the image can't be mounted, a second way
  is tried (losetup), and the installer shows the reason (errors + kernel messages) instead of
  "not enough free space?". The kernel is also allowed to read the image, in case SELinux blocked it.
- Fixed: with the image, the module would have refused to start ("module files missing").

## v1.2.0
- Magisk and APatch are supported too (besides KernelSU and its forks). Magisk needs v28+ for the
  Action button; the quick settings tile and home-screen icon work with any version.
- Works on kernels that refuse files from /data in overlay mounts (seen on crDroid: the module stayed
  inactive with "overlay /system/lib64 failed"). The installer detects this and packs the module's files
  into an image instead.
- Works alongside modules that change the same folders (e.g. Dolby/audio mods in /vendor/lib64): when
  switching the HAL live would break the other module's files, the switch is applied after a reboot
  instead (the tile/app says so). The odm camera config is mounted only over /odm/etc/camera now.

## v1.1.1 (not released, included in v1.2.0)
- Fixed: with some module setups (e.g. a mount metamodule that remounts whole partitions), switching
  to the ROM's HAL worked but the module still reported the OnePlus HAL, and switching back did
  nothing. The module now checks which mount is actually in use instead of whether one exists, and
  only unmounts its own.
- Any custom ROM on the OnePlus 12 with Android 17 is accepted now (experimental), not only ones that
  identify as LineageOS: crDroid was refused. The installer still refuses other devices, other Android
  versions and stock OxygenOS/ColorOS. The ROM name is only used as a label (LineageOS, crDroid, else "ROM").
- When a mount or unmount fails, the log says why (error, what's mounted there, kernel messages), and
  after boot it notes if another mount sits on top of the module's.

## v1.1.0
- Experimental support for LineageOS-based ROMs on the OnePlus 12 (Android 17). On those the HAL
  switch calls the ROM's own HAL "LineageOS". Nothing changes on YAAP.
- The HAL switch finds the camera provider service from the vendor's init files instead of assuming
  its name.
- More details in the log (ROM, camera count), and the installer shows them if it refuses a ROM.

## v1.0.2
- Fixed: HEIC photos ("High efficiency image" and "10-bit color" in the camera's settings) were saved
  without the picture. They now save correctly, including EXIF (date taken, exposure, ...). DerpFest
  has the same bug.

## v1.0.1
- Fixed: opening the OnePlus camera while another camera app still had a camera open (any lens,
  including the front camera) crashed the camera HAL. The other app now loses the camera cleanly,
  like on stock Android, and the OnePlus camera opens.

## v1.0.0 — first public release
- OnePlus camera (DerpFest port) with the OnePlus camera HAL on YAAP, OnePlus 12
- OnePlus Photos (gallery) with the photo editor
- Live switch between the OnePlus and YAAP camera HALs: KernelSU Action button, quick settings tile,
  home-screen icon
- Lens row / zoom ring position fix
- Bootloop protection: the module disables itself if a boot doesn't finish

(Internal test builds before this were numbered v1.0–v1.5.)
