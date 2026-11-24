# Building the module

The result is `build/opcamera_yaap-<version>.zip`, the same KernelSU module as the releases.

## Requirements
- **Shell:** bash. On Windows use Git Bash; WSL is used automatically for `python3`/`patchelf` if they
  aren't available natively.
- **Android SDK:** build-tools 36.0.0 and platform `android-36`. **NDK:** r29.
- **JDK 17** (for apksigner).
- **python3** and **patchelf 0.18**. Another patchelf version gives a different `libcsextimpl.so`,
  which the build rejects.
- **For the payload:** Linux or WSL with `debugfs` (e2fsprogs) and `fsck.erofs` (erofs-utils).
  [payload-dumper-go](https://github.com/ssut/payload-dumper-go) is only needed to read the ROM zip directly.
- **The ROM:** DerpFest-v17 waffle `20261005` (see [PAYLOAD.md](PAYLOAD.md)).

Tool locations are detected automatically. Override them with `ANDROID_HOME`, `NDK`, `BUILD_TOOLS`,
`PLATFORM`, `JAVA_HOME`, `PYTHON` and `PATCHELF` (see `tools/env.sh`).

## Steps
```sh
# 1. payload/ from the DerpFest ROM (Linux / WSL)
tools/extract_payload.sh DerpFest-v17-20261005-17-05-waffle-Official-Stable.zip
# 2. camera APK: add uses-library oplus.fwk, hide the Hi-Res and Pro video modes and the Video HDR switch
#    (dex patches), re-sign.
#    SMALI_JAR: a jar with smali + baksmali, e.g. jadx-<version>-all.jar; KEYSTORE/KS_PASS/KS_ALIAS: your key
SMALI_JAR=/path/to/jadx-1.5.6-all.jar \
tools/repack_camera_apk.sh payload/sys/system_ext/priv-app/OplusCamera/OplusCamera.apk \
                           payload/sys/system_ext/priv-app/OplusCamera/OplusCamera.apk
# 3. build everything
tools/build.sh
```

`tools/build.sh` runs:
1. `build_native.sh`: `binderpatch`, `relink`, `libapsfix.so`, `libcsext_shim.so`, `libheiffix.so`, and the
   position-dependent stubs (camera eviction, characteristics hooks, crop hook; the last two are checked
   against the copies embedded in their patchers).
2. `build_apps.sh`: `OPCameraZoomFix.apk`, signed with `KEYSTORE`/`KS_PASS`/`KS_ALIAS`
   (default: `~/.android/debug.keystore`).
3. `build_module.sh`: checks the payload against `payload/MANIFEST.sha256`, applies the binary patches,
   assembles `module/` + `files/` + payload + our builds, and zips it.

`build_module.sh` refuses to:
- use a payload or a patched binary that differs from the tested one;
- include a file without a tested SELinux label (`tools/labels.txt`);
- include an APK with `sharedUserId` (a shared system uid bootlooped the phone during development);
- overwrite an existing zip of the same version (bump `module/module.prop`, or set `FORCE=1`).

## Versioning
`module/module.prop`: `version=vMAJOR.MINOR.PATCH` and `versionCode=MAJOR*10000 + MINOR*100 + PATCH`
(the build checks both). Add an entry to `CHANGELOG.md` for each release.
