# Changelog

Versions are `vMAJOR.MINOR.PATCH`: PATCH = fixes, MINOR = new features, MAJOR = breaking changes
(e.g. dropping support for an older YAAP). `versionCode` = MAJOR×10000 + MINOR×100 + PATCH.

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
