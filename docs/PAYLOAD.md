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
| `hal/odm/...`, `hal/vendor/...` | `/odm`, `/vendor` | the OnePlus camera HAL: `camera.qcom.so`, CamX/CHI nodes, sensor modules and tuning, configs, OnePlus algorithm libraries |

The newer DerpFest `20261115` has identical camera files except a rebuilt `cameraserver` /
`libcameraservice.so` (a flashlight-brightness change). The camera service patch below is made for
the `20261005` binary, so take the payload from that build.

## 2. Prepared once: `OplusCamera.apk`
DerpFest's APK needs `<uses-library android:name="oplus.fwk" android:required="false"/>` on YAAP
(the library is declared by `files/.../oplus_fwk_library.xml`). `tools/repack_camera_apk.sh` adds it
(`tools/axmlpatch.py`), then zipaligns and re-signs the APK.

The released module is signed with the maintainer's key, so your own build signs with another key
(`KEYSTORE`, default: the Android debug key) and its hash differs from the manifest. The build accepts
that with a warning. It works the same, but moving between differently signed builds resets the
camera app's data.

## 3. Patched at build time (`tools/build_module.sh`)
Every patcher checks the input and output hashes, so it only ever produces the tested file.

| file | patch | why |
|---|---|---|
| `cameraserver` | `tools/patch_cameraserver.py` + `src/evictfix/cave.s` | the OnePlus camera must evict other camera apps instead of sharing the HAL (sharing crashes the OnePlus HAL) |
| `libcsextimpl.so` | `patchelf --add-needed libcsext_shim.so` (patchelf 0.18) | it needs three `CameraSessionStats` constants that YAAP's `libcamera_client.so` lacks |
| `libAlgoProcess.so` | `tools/patch_algoprocess.py` | YAAP's `AHardwareBuffer_lockPlanes` returns one plane for QTI P010; the import is redirected to `libapsfix.so` |

## 4. Built from source (`tools/build_native.sh`, `tools/build_apps.sh`)
| output | source |
|---|---|
| `libcsext_shim.so` | `src/shim` |
| `libapsfix.so` | `src/apsfix` |
| `bin/binderpatch` | `src/binderpatch`: patches the phone's own `libbinder.so` at boot (4 MB binder buffer instead of 1 MB) |
| `HalSwitch.apk` | `src/halswitch`: "Camera HAL" quick settings tile and launcher icon |
| `OPCameraZoomFix.apk` | `src/zoomfix`: resource overlay for the zoom ring / lens row |

## 5. Our own files (`files/`)
`oplus_fwk_library.xml`, `hiddenapi-package-oplus-whitelist.xml` and `privapp-permissions-oplus.xml`
(DerpFest's list plus `com.oplus.camera.sandbox.permission.SANDBOX_PROVIDER` for the gallery).
