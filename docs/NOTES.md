# OPlus camera on YAAP (OnePlus 12 / waffle) - KernelSU module work

Live-tested state (2026-11-17): OPlus camera (com.oplus.camera) fully working on YAAP-17
(CP2A.260605.016) with DerpFest's OOS16 (U.R4T3) camera HAL overlaid globally.

## Pieces
| Stage | What | Script |
|---|---|---|
| A | DerpFest cameraserver + libcameraservice + DerpFest libcsextimpl (+ src/shim/csext_shim.cpp) | dev/live_cs.sh |
| B | OplusCamera.apk + OplusPermissionDefiner (NO OplusAppPlatform: sharedUserId=android.uid.system bootloops) | dev/live_app.sh |
| C | DerpFest odm/vendor camera HAL files (payload/hal/, 44 files + libui-stock.so) | dev/live_hal.sh |
| - | sepolicy for priv_app_36 (dev/ocam_sepolicy.rule; the module uses module/sepolicy.rule) | applied with ksud sepolicy patch |
| - | libbinder 4 MB binder VM | dev/zr.sh (+ zr_watch.sh auto-rollback) |

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

### cameraserver (DerpFest system, md5 5547ec78e5db7deed92612e81739508c)
CameraService is linked statically into /system/bin/cameraserver (the shipped libcameraservice.so is not
what runs). CAF's isPrivilegedClient() (persist.vendor.camera.privapp.list = com.oplus.camera) cleared
the eviction lists, so another app kept its camera and the OnePlus HAL crashed when shared; and even
with eviction, front (cost 33) + OnePlus on camera 2 (cost 66) fit in 100 and crashed the HAL.
- bl isPrivilegedClient -> mov w0,#0 at 0xf14fc (handleEvictionsLocked) and 0xf44d8 (finishConnectLocked)
- bl wouldEvictLocked at 0xf14ec -> stub (src/evictfix/cave.s) in the zero padding after .plt (0x37eee0,
  R+X PT_LOAD extended by 0x40): the privileged client's descriptor cost is set to 100
- tools/patch_cameraserver.py, result md5 ca45c8570630cb84800c7775200620d3
- Debugging tips: never pipe `dumpsys media.camera` into `head` (the HAL gets SIGPIPE and dies); uprobes
  only attach to processes started after they are registered.

## Gotchas
- KernelSU live sepolicy patches don't bump selinux status `policyload`, so userspace AVCs
  (servicemanager) keep cached denials. Live fix: dd /sys/fs/selinux/policy -> /sys/fs/selinux/load
  (single write). Not an issue at boot.
- adb `su -c "a; b"` only runs `a` as root: push scripts and run them.
- Never restart zygote / reboot without the user's OK; always keep an auto-rollback.

## Known issues
- Slow-mo: only 60 real frames/s at 120/240/480 fps; the viewfinder shows 1 of 8 (7.5 fps). The same on
  fully stock YAAP (its own cameraserver + HAL; plain AOSP constrained-high-speed test app, bright light),
  so it's a YAAP kernel/platform limit, not fixable from the module. Forcing cameraserver batching
  (the HAL advertises batch_size_max = 1) doesn't help: batch 8 overflows the HAL's 8-buffer limit,
  batch 4 still gives 60 fps.
- The OnePlus HAL replaces YAAP's HAL for every app; per-app automatic switching was tried and dropped
  (~6.5 s per switch, kills open camera apps). The module has a manual switch instead.

## KernelSU module (module/, tools/build.sh -> build/opcamera_yaap-<ver>.zip)
- No system/ dir: KSU 3.x has no metamodule here, and we want our own boot guard. post-fs-data.sh mounts
  everything in init's ns (overlays from /data/adb/modules/opcamera_yaap/files/{sys,hal}, cameraserver
  bind+suid, libbinder bind from /data/adb/opcamera/libbinder.so).
- libbinder is patched on-device at boot by bin/binderpatch (src/binderpatch) from the ROM's own lib,
  cached by source md5 -> re-done automatically after YAAP updates; skipped if pattern not found.
- Boot guard: /data/adb/opcamera/boot_pending set at post-fs-data, cleared by service.sh after
  boot_completed + system_server stable 20 s. Still present next boot -> module disables itself.
  No boot_completed within 300 s -> service.sh disables module and reboots.
- HAL mode (oos|yaap) in /data/adb/opcamera/hal_mode; Action button = live switch (refuses while a camera is open).
- Zoom ring / lens-row fix: src/zoomfix RRO (dimen zoom_arc_seekbar_bg_circle_radius 199dp -> 228dp = 798 px > W/2, so the ring is a flat arc and the lens row lands where stock puts it; since v2.0.3 also the Pro controls moved down, see "Lens row vs Pro controls"), preinstalled
  in /product/overlay (user-installed RROs need the target's cert). Non-static, enabled by service.sh unless
  The overlay value must also be in values-sw380dp (target defines sw320dp-2128x1080 etc.; an RRO entry only wins if its config is >= as specific), link with --no-resource-deduping.
  /data/adb/opcamera/zoomfix = off. Cause: am.w.z4 sagitta term r - sqrt(r^2 - (W/2)^2) with r = 199dp = 697px
  < 720 = W/2 -> NaN -> row ~280 px too high at 1440 px width.
- Labels come from the live-tested staging (tools/labels.txt); build refuses unlabeled files and APKs with sharedUserId.

## OnePlus gallery (v1.4)
- DerpFest's `system_ext/priv-app/OppoGallery2/OppoGallery2.apk` (com.oneplus.gallery 16.35.10, EU/GDPR
  build, no sharedUserId), unmodified, in `payload/app/system_ext/priv-app/`. md5 checked by the build.
- Must be a priv-app: the photo editor calls the camera SDK (libMsEffectSdk, libAPSClient-*-jni), which loads
  /odm libs through the sphal namespace (libmsnativefilter, libalog, libAlgoProcess...). YAAP labels those
  vendor_file; DerpFest's vendor_file_contexts labels them same_process_hal_file. As a normal app
  (untrusted_app_34) the loads fail and the editor segfaults on a null function pointer. As a priv-app it
  runs as priv_app_36, which already has `allow priv_app_36 vendor_file file {read open getattr map execute}`.
- privapp allowlist: added com.oplus.camera.sandbox.permission.SANDBOX_PROVIDER (signature|privileged,
  defined by the camera); every other privileged permission it requests was already listed.
- Not working (same on DerpFest): downloadable editor plugins/models. Their server URLs come from the OPlus
  AppFeatureProvider (content://com.oplus.customize.coreapp.configmanager.configprovider.AppFeatureProvider,
  keys like com.oplus.gallery3d.videoeditor_url), which neither ROM has, so the URL is empty.

## v2: YAAP's own camera HAL (2026-11-24)
YAAP ships OnePlus's camera HAL (16.0.10 blobs; DerpFest's is 16.0.8). The OnePlus camera works on it with:
- `libOplusSecurity.so` (same_process_hal_file) added to /odm/lib64; the app-side libs/configs/licences
  (libAlgoProcess & co.) as before.
- libui: camera.oemlayer, the mvgsat/sstabphoto/dewarp nodes, libEIS/libEISLive/libHIS, libmvgcommon and
  libsharebuffer_impl were built against OnePlus's libui; with AOSP's libui.so the provider heap gets
  corrupted (GraphicBuffer layout). DerpFest patchelfs them to libui-stock.so. The module ships
  libui-stock.so as /vendor/lib64/libus.so (SONAME stays libui-stock.so; nothing else loads that name) and
  bin/relink renames the 8-byte NEEDED string in copies of the ROM's own files at boot
  (/data/adb/opcamera/relink, keyed by md5 of the tool and the ROM files), bind-mounted over the originals.
- Characteristics: YAAP's sensor drivers report the full quad-bayer arrays and 50 MP stream sizes; the
  OnePlus camera then picks 50 MP streams for everything. charfilter.cpp (hooked into
  CameraService::getCameraCharacteristics, entry + exit, caller = AttributionSourceState.packageName,
  /proc/<pid>/cmdline is not readable from cameraserver) trims sizes above half the active array for
  com.oplus.camera only, sets QCFA remosaic type 1, adds the bokeh sizes tag if missing.
- Photo ratios: in photo mode the preview size comes from the app config's live-photo lists
  (`com.oplus.feature.capture.mode.livephoto[.front].size`, one size per ratio index: 0 square, 1 4:3,
  2 16:9, 3 full, ..., 12 wide; values read from the running app's heap) and
  `com.oplus.camera.livephoto.pre.full.size.configure`. YAAP's camx rejects (CheckValidStreamConfig) the
  ones it doesn't list: 1440x1440, 2136x1200, 2640x1200 -> 1:1, 16:9 and Full froze the camera (preview
  config failed). 65:24 "wide" (2136x788; no 2.71 YUV sizes at all) -> session NPE, black screen, ratio
  persisted. common.sh unitcfg_prepare copies the ROM's camera_unit_config with these keys added to
  "vendor_tag_type_values" (read before the encrypted oplus_camera_config, but only once parsed, ~5 s after
  launch: see Dolby Vision below) and bind-mounts it: same-ratio HAL
  sizes, and an empty wide.frame.ratio.support.modelist (option hidden; a persisted "wide" falls back to the
  default on the next launch, RatioPresenter.n1 -> q1).
- Green video at 30 fps in low light (frames R=B=0 with luma: chroma plane empty; 60 fps uses other
  pipelines and is fine). Detector for dark scenes: G > 25 && G > 3*(R+B) (R<20,B<20,G>60 misses them).
  - normal video (op mode 0x830B, SAT): isEnableVIULL = TRUE + [isEnableVIULLMap] -> MultiCameraSATVIULL0
    pipeline in low light: green 374/479 (dim), 149/180 (lamp light). isEnableVIULL = FALSE ->
    MultiCameraCustomSATEIS0, 0/181, staggered HDR (UnifiedHDR1) still on. Turning SHDR off instead
    (Mode[0]/[1] op mode 0xFFFF) did NOT help: fully green. FIX (v2.0.3+): common.sh hwcfg_prepare, a copy
    of CameraHWConfiguration.config with exactly that 1 line changed (refuses anything else), bind-mounted
    at boot (the HAL reads it when the provider starts; post-fs-data is before that). VIULL is only used for
    OnePlus op modes + [3rdAppEnableVIULLMap] (hd.camera, cn.ninebot.ninebot); Photon's HDR (0x8021) untouched.
  - Pro video (app mode "masterVideo", 0x80A3; 0x80A4 with EIS), NOT fixed: [SHDRTypeMatching] Mode[3]/[4] ->
    UnifiedHDR_0_cam_0 + OfflinePreview_0_cam_0. At auto ISO in a dim room (ISO 3200) the frames are solid
    (0,135,0) = all-zero YUV, i.e. not written at all; also with the ROM's config, with VIULL off and with
    seamless_support 0, and (v2.0.4 full test, ROM config A/B) also at manual ISO 50 1/60: 121/131 green in a
    recording; so not gain-dependent, scene-dependent. v2.0.3 also set Mode[3]/[4] op mode 0xFFFF
    (-> OplusVideoPreviewRealTime + VideoNoEISPreviewNoEISOffline): fine at ISO 50 (which is how it was
    wrongly validated) but still green at auto ISO, and a colour tint in normal light -> reverted in v2.0.4.
  "dol_switch isModeSwitched" logs every frame in all video modes: not a symptom. Gralloc4 "get(...19/20/21)
  failed" per frame comes from screenrecord.
- Dolby Vision (Video sub-menu; 60 fps: op 0x8021 + OplusDolbyVideoEIS3PreviewEIS2Offline; 30 fps: 0x830B +
  UnifiedHDR_0, preview green): never records on YAAP, also with the ROM's HAL config: StagefrightRecorder
  "Failed to create video encoder" (Dolby profile; the app also sets OnePlus-only OplusUserData), then the
  app resets it to off. Not hidden: com.oplus.feature.video.dv.support comes from the encrypted
  oplus_camera_config. A camera_unit_config override is too late (CameraConfig initialises at ~0 s,
  CameraConfigHelper parses camera_unit_config ~5 s later; flags read before that fall back to ApsUtils' map
  and stay cached), and even the app's own override_config_data prefs (highest priority in CameraConfig.t)
  didn't remove it: the Video mode's option list comes from camera_unit_feature_config.protobuf
  (key_video_dolby). Left visible in v2.0.4.
  At 60 fps with key_video_dolby=on, Video mode hangs: camera opened (dumpsys media.camera: Device status
  UNCONFIGURED), streams never configured, app logs APP_MISS_FRAME; black viewfinder, no top bar, so the
  user can't switch it off (fixed on the phone by appending key_video_dolby="off" to
  files/mmkv/com.oplus.camera_preferences_0 with size + CRC32 updated in it and its .crc: data[0:4] size,
  crc[0:4] digest, crc[0x1c] size, crc[0x20]/[0x24] last confirmed size/digest; camera force-stopped).
  DONE in v2.0.5: tools/patch_videohdr.py, Video mode (com/oplus/camera/module/a, ck/l QuickVideo extends it;
  ck/u0 = abstract video base, ck/p = slow video with its own func_slow_hdr) getSupportFunction("func_hdr")
  -> false. Users: u0.z4 (key_video_hdr / key_video_dolby offered?), a.Cd (HDR on?), BaseMode.U6,
  CameraManager.M0 and pj.s4.u (dispatch to the current mode), xj/g$c. BaseMode.Z6 is the app's own
  "turn Dolby off" (writes off when Cd()). Checked: whole-APK dex2oat verify, no messages in the patched
  methods, 0 hard failures (soft-failure lists vary between runs: log loss).
- Lens row vs Pro controls: the zoom container (am.w.z4) is bottom-aligned, height LayoutUtil.f14709d +
  arc height; the lens row is drawn zoom_arc_seekbar_focus_circle_center_y below its top. The Pro panel
  (dm.b) is bottom-aligned at the same f14709d (control panel height), so the overlap is the same in every
  mode (no Pro-specific offset; setCenterYOffset only for recording). Measured (uiautomator): main_bar_id
  [2095..2305], labels 2139..2180, values 2184..2261, lens row ~2125..2155. hs_main_bar_item_layout (and
  master_main_bar_item_layout) place title/value from the item's top: hs_main_mode_bar_item_title_margin_top
  12.5dp, _value_margin_top 25.5dp, value height 22dp, item 60dp -> both +12dp in the zoomfix RRO (labels
  ~43 px lower, values still inside the bar). (Stock OnePlus 12 goes through c8.c Density560Width1240ResDecision
  with radius_1240 209dp / center_y_1240 65dp; moving the lens row up was rejected by the user.)
- Portrait: empty physical-camera metadata -> NULL -> CameraMetadata::append crash (patch_cs_physmeta).
- Offline reprocess crop (apscrop/apsfix): APS crops in binned-frame coordinates. In low light at 3x/6x
  the main camera stays master and APS shifts the crop by the SAT inter-camera shift (e.g. -52,-52 in
  4096 space), so the match rule compares the doubled vs undoubled centre distance to the HAL crop
  (4*d1 < d0) instead of a fixed tolerance.
- XPAN (2912x7872 JPEG): in a dim room the saved photo is plain green (mean 25,158,11, always ~874 KB) also with
  the "Original" filter; same with the ROM's CameraHWConfiguration.config and the ROM's camera_unit_config
  (A/B in the v2.0.4 full test), so not caused by the module's config copies. With a filter it's green in any
  light (Meishe capture render writes nothing). Cause not found.
- Hiding modes (Hi-Res, Pro video) via config does NOT work. The mode list is a SQLite DB in the app's data
  (databases/mode_data.db, table mode_info; xm/e.h/i/j), built only when the DB is missing (or the app version
  string changes, then f() only drops movie=3/professional=4 if unsupported) and read from there afterwards.
  Keys: com.oplus.feature.high.pixel.support (r7.a "highPixel", id 31), com.oplus.feature.movie.mode.support
  (mode 3; on this phone Pro video is "masterVideo", id 36: xm/e.h() adds it instead of "movie" when c7.e.i()). Even a fresh rebuild ignores a camera_unit_config override: the DB is built at +0 ms, the file is
  parsed at +9..+42 ms (same race as Dolby Vision). The in-app editor (pencil) only rearranges. DONE in v2.0.5
  with a dex patch: tools/patch_modelist.py skips "highPixel"/"masterVideo"/"movie" rows in xm/e.p() (next to the "sticker"
  skip; v4 = mode_name, v1 scratch, jump to :goto_5d), so old saved lists are filtered too. Other mode_info
  users: q(id) lookups by id (still find the rows, harmless), l6/p7 "delete from mode_info" (editor save).
  Checked: ART verifier (dex2oat --compiler-filter=verify -verbose:verifier on classes12) no failures in p().
  The new APK is signed with keys/opcamera-release.jks (outside the repo; v2.0.0-v2.0.4 key "CN=opcamera,
  O=port" is lost). Expected a data wipe, but on the phone (Android 17) PMS logged "System package
  com.oplus.camera signature changed; retaining data": settings, mode list and permissions were kept.
