# Payload: where every shipped file comes from

The module ships proprietary OnePlus/DerpFest files. They are **not in this repository**: you extract
them from the DerpFest ROM into `payload/` (git-ignored), and `payload/MANIFEST.sha256` pins the
exact tested versions. The build refuses a payload that differs (except for the camera APK's
signature, see below).

## 1. Unmodified DerpFest files (`payload/`)
Source: **DerpFest-v17 waffle `20261005`** (`DerpFest-v17-20261005-17-05-waffle-Official-Stable.zip`).
`tools/extract_payload.sh` copies them from the ROM's `system`, `system_ext`, `odm` and `vendor` images:

| payload path | taken from | what |
|---|---|---|
| `sys/system/bin/cameraserver`, `sys/system/lib64/*` | `/system/...` | DerpFest's camera service (CameraService is linked statically into `cameraserver`) and its libraries |
| `sys/system_ext/lib64/*` | `/system_ext/lib64` | OnePlus camera service extension (`libcsextimpl.so`) and its deps, the camera app's JNI libraries |
| `sys/system_ext/framework/*.jar` | `/system_ext/framework`, `oplus-fwk.jar` from `/system/framework` | OnePlus camera unit SDK, OnePlus framework classes |
| `sys/system_ext/priv-app/OplusCamera`, `OppoGallery2`, `app/OplusPermissionDefiner` | `/system_ext/...` | the OnePlus camera, OnePlus Photos, OnePlus permission definitions |
| `sys/system_ext/etc/{permissions,default-permissions}/*` | `/system_ext/etc/...` | features, default permission grants |
| `hal/odm/...`, `hal/vendor/...` | `/odm`, `/vendor` | DerpFest's OnePlus camera HAL. Since v2.0.0 only part of it is shipped (the ROM's own HAL is used): `libOplusSecurity.so`, the camera app's processing libraries (`libAlgoProcess.so`, `libAlgoInterface.so`, `libOPAlgoCamFaceBeautyCap.so`), `libYTCommon.so` (text mode: YAAP's copy has unloadable program headers), licences, the APS/algo-switch configs, and `libui-stock.so` (shipped as `vendor/lib64/libus.so`) |

The newer DerpFest `20261115` has identical camera files except a rebuilt `cameraserver` /
`libcameraservice.so` (a flashlight-brightness change). The camera service patch below is made for
the `20261005` binary, so take the payload from that build.

## 2. Prepared once: `OplusCamera.apk`
`tools/repack_camera_apk.sh` changes DerpFest's APK in two places, then zipaligns and re-signs it:
- manifest: `<uses-library android:name="oplus.fwk" android:required="false"/>`, needed on YAAP (the library
  is declared by `files/.../oplus_fwk_library.xml`), added by `tools/axmlpatch.py`;
- `classes12.dex`: `tools/patch_modelist.py` hides the Hi-Res and Pro video modes. The camera reads its mode
  list from its own database in `xm/e.p()`; the patch skips the `highPixel` and `masterVideo` (and `movie`) rows there, like the
  method already does for the `sticker` mode (config switches can't do it, see docs/NOTES.md). Done with
  baksmali/smali (`SMALI_JAR`);
- `classes12.dex`: `tools/patch_videohdr.py` hides Video mode's HDR (Dolby Vision) switch: the Video mode class
  (`com/oplus/camera/module/a`, also used by QuickVideo) reports `func_hdr` as unsupported. Everything about
  the switch checks that: whether it's offered, whether HDR is on. Dolby Vision never records on YAAP, and at
  60 fps the mode hung with it on (camera opened, streams never configured), so it couldn't be turned off.

  smali's dex layout isn't reproducible, so the script disassembles the result and checks that only the two
  patched classes changed and that each matches the tested patch.

Since v2.0.5 the released module is signed with the maintainer's `opcamera-release` key (v2.0.0–v2.0.4 used
an older key that was lost). Your own build signs with another key (`KEYSTORE`, default: the Android debug
key), so its hash differs from the manifest. The build accepts that with a warning. It works the same: when a
system app's key changes, Android 17 keeps its data ("System package ... signature changed; retaining data").

## 3. Patched at build time (`tools/build_module.sh`)
Every patcher checks the input and output hashes, so it only ever produces the tested file.

| file | patch | why |
|---|---|---|
| `cameraserver` | `tools/patch_cameraserver.py` + `src/evictfix/cave.s` | the OnePlus camera must evict other camera apps instead of sharing the HAL (sharing crashes the OnePlus HAL) |
| `cameraserver` | then `tools/patch_cs_physmeta.py` | YAAP's HAL sends an empty physical-camera result in portrait captures; `CameraMetadata::append(NULL)` crashed |
| `cameraserver` | then `tools/patch_cs_chars.py` + `src/csfix/charstub.s` | hooks `getCameraCharacteristics` into `libcsext_shim.so` (`src/shim/charfilter.cpp`): for `com.oplus.camera` only, the 50 MP sizes of the quad-bayer sensors are hidden (the camera expects binned sizes, as on OxygenOS) |
| `libcsextimpl.so` | `patchelf --add-needed libcsext_shim.so` (patchelf 0.18) | it needs three `CameraSessionStats` constants that YAAP's `libcamera_client.so` lacks |
| `libAPSClient-cmd-jni.so` | `patchelf --add-needed libheiffix.so` (patchelf 0.18) | HEIC: it looks the encoder parameters up by older names than the OnePlus HAL sends (see `src/heiffix`) |
| `libAlgoProcess.so` | `tools/patch_algoprocess.py` | YAAP's `AHardwareBuffer_lockPlanes` returns one plane for QTI P010; the import is redirected to `libapsfix.so`. HEIC: the EXIF block is passed on with its real size instead of being cut off at its first zero byte |
| `libAlgoInterface.so` | `tools/patch_algointerface.py` | `textEnhanceUninit()` reads the text-enhance engine without checking it; after a failed register, or a second unregister, the engine is NULL and the camera app crashed when the camera closed. A 5-instruction trampoline in the padding after the code segment (segment grown by 20 bytes) returns the function's own error instead |
| `libAlgoProcess.so` | then `tools/patch_apscrop.py` + `src/apscrop/cropstub.s` | offline reprocessing sends its crop in binned-frame coordinates; YAAP's sensor drivers report full quad-bayer active arrays, so `libapsfix.so` doubles the crop when it matches the HAL's own |
| `com.oplus.camera.unit.sdk.jar` | `tools/patch_unitsdk.py` (dex edited in place) | Hi-Res mode: the raw outputs of the 1x camera are requested at the picture size (8192x6144) instead of the largest RAW size of the trimmed characteristics (4096x3072), which the HAL rejected |

## 4. Built from source (`tools/build_native.sh`, `tools/build_apps.sh`)
| output | source |
|---|---|
| `libcsext_shim.so` | `src/shim`: `CameraSessionStats` constants; the OnePlus camera's characteristics filter |
| `libapsfix.so` | `src/apsfix` |
| `libheiffix.so` | `src/heiffix`: maps the camera JNI library's old HEIC parameter names to the HAL's (`..._INT_` -> `..._INT_BASIC_`) |
| `bin/binderpatch` | `src/binderpatch`: patches the phone's own `libbinder.so` at boot (4 MB binder buffer instead of 1 MB) |
| `bin/relink` | `src/relink`: at boot, makes copies of 9 of the ROM's OnePlus HAL libraries with `DT_NEEDED libui.so` renamed to `libus.so` (same length, one string changed; refuses anything ambiguous). They are bind-mounted over the originals |
| `OPCameraZoomFix.apk` | `src/zoomfix`: resource overlay for the zoom ring / lens row (ring radius; position of the Pro and Master modes' manual controls, which sat under the lens row) |
| `camera_unit_config` (not shipped) | made at boot by `module/common.sh` (`unitcfg_prepare`): a copy of the ROM's `/odm/etc/camera/config/camera_unit_config` with 4 values added (photo-mode preview sizes YAAP's HAL accepts; the 65:24 ratio hidden), bind-mounted over the original |
| `CameraHWConfiguration.config` (not shipped) | made at boot by `module/common.sh` (`hwcfg_prepare`): a copy of the ROM's `/odm/etc/camera/CameraHWConfiguration.config` with one line changed, `isEnableVIULL = FALSE` (the video low-light path, green at 30 fps on YAAP's HAL), bind-mounted over the original |

## 5. Our own files (`files/`)
`oplus_fwk_library.xml`, `hiddenapi-package-oplus-whitelist.xml` and `privapp-permissions-oplus.xml`
(DerpFest's list plus `com.oplus.camera.sandbox.permission.SANDBOX_PROVIDER` for the gallery).
