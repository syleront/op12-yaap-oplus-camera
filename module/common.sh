# Shared by all module scripts. The caller sets MODDIR.
# Nothing in this module is mounted by KernelSU itself (no system/ dir): every mount is done
# here, in init's mount namespace, and is gone after a reboot.

ST=/data/adb/opcamera                 # state kept across module updates
LOG=$ST/log.txt
F=$MODDIR/files
NS="nsenter -t 1 -m --"
RP=/data/adb/ksu/bin/resetprop; [ -x $RP ] || RP=resetprop
ACTIVE=/dev/opcamera.active           # tmpfs marker: our mounts are up this boot
LOCK=/dev/opcamera.lock
OPLUS=com.oplus.camera
EXPECT_SDK=37

# Overlay targets. sys = cameraserver stack + OPlus camera app (always on while the module is active)
SYS_TGTS="/system/lib64 /system_ext/lib64 /system_ext/priv-app /system_ext/app /system_ext/framework /system_ext/etc/permissions /system_ext/etc/default-permissions /system_ext/etc/sysconfig /product/overlay"
OPT_TGTS="/product/overlay"     # optional: skipped (not fatal) if missing
# hal = OnePlus (OOS16) camera HAL files, mounted only in "oos" HAL mode
HAL_TGTS="/odm/lib64 /odm/etc /vendor/lib64"

log() { echo "$(date '+%m-%d %H:%M:%S') [$1] $2" >> $LOG; }
trim_log() { [ -f $LOG ] && [ $(wc -l < $LOG) -gt 400 ] && { tail -n 200 $LOG > $LOG.tmp; mv $LOG.tmp $LOG; }; }

set_desc() { sed -i "s|^description=.*|description=$1|" $MODDIR/module.prop; }
hal_name() { [ "$1" = oos ] && echo "OnePlus HAL" || echo "YAAP HAL"; }
hal_mode() { m=$(cat $ST/hal_mode 2>/dev/null); [ "$m" = yaap ] && echo yaap || echo oos; }
desc_active() {
    if [ "$(hal_cur)" = oos ]; then
        set_desc "Active | camera HAL: OnePlus (OnePlus camera works). Press Action to switch to the YAAP HAL."
    else
        set_desc "Active | camera HAL: YAAP (OnePlus camera won't open). Press Action to switch to the OnePlus HAL."
    fi
}

# Returns a reason on stdout and fails if this ROM/device is not what the module was built for.
preflight() {
    sdk=$(getprop ro.build.version.sdk)
    [ "$sdk" = "$EXPECT_SDK" ] || { echo "Android SDK $sdk, module is for SDK $EXPECT_SDK"; return 1; }
    case "$(getprop ro.build.fingerprint)" in
        */yaap_waffle/waffle:*) ;;
        *) echo "not YAAP on OnePlus 12 (waffle)"; return 1 ;;
    esac
    [ -f $F/sys/system/bin/cameraserver ] || { echo "module files missing, reinstall"; return 1; }
    return 0
}

# SELinux labels: copied from the live-tested setup (files/labels.txt); anything unlisted gets
# the label of the real path it shadows (or of its nearest existing parent).
apply_labels() {
    chown -R 0:0 $F
    find $F -type d -exec chmod 0755 {} +
    find $F -type f -exec chmod 0644 {} +
    chmod 0755 $F/sys/system/bin/cameraserver $MODDIR/bin/binderpatch
    while read -r lbl p; do [ -e "$F/$p" ] && chcon "$lbl" "$F/$p"; done < $F/labels.txt
    find $F/sys $F/hal -mindepth 1 | while read -r p; do
        rel=${p#$F/}; grep -q " $rel\$" $F/labels.txt && continue
        real=/${rel#*/}
        while [ ! -e "$real" ] && [ "$real" != / ]; do real=${real%/*}; [ -z "$real" ] && real=/; done
        chcon "$(ls -dZ "$real" | awk '{print $1}')" "$p"
    done
}
labels_ok() {
    ls -Z $F/sys/system/bin/cameraserver | grep -q cameraserver_exec &&
    ls -Z $F/hal/odm/lib64/libOplusSecurity.so | grep -q same_process_hal_file &&
    ls -dZ $F/sys/system_ext/priv-app | grep -q system_file
}

is_ours() { grep -q "lowerdir=$1:" /proc/1/mountinfo; }

mount_sys() {
    for t in $SYS_TGTS; do
        [ -d "$F/sys$t" ] || continue
        if [ ! -d "$t" ]; then
            case " $OPT_TGTS " in *" $t "*) log W "optional target $t missing, skipped"; continue ;; esac
            log E "target $t does not exist"; return 1
        fi
        $NS mount -t overlay -o "lowerdir=$F/sys$t:$t" opcamera "$t" || { log E "overlay $t failed"; return 1; }
    done
    # /data is nosuid; a plain bind inherits that and SELinux then refuses init's domain
    # transition into cameraserver, so remount the bind with suid
    $NS mount -o bind $F/sys/system/bin/cameraserver /system/bin/cameraserver || { log E "bind cameraserver failed"; return 1; }
    $NS mount -o remount,bind,suid /system/bin/cameraserver || { log E "remount cameraserver suid failed"; return 1; }
    return 0
}

umount_all() {
    hal_down
    grep -q " /system/lib64/libbinder.so " /proc/1/mountinfo && $NS umount -l /system/lib64/libbinder.so
    grep -q " /system/bin/cameraserver " /proc/1/mountinfo && $NS umount -l /system/bin/cameraserver
    for t in $SYS_TGTS; do is_ours "$F/sys$t" && $NS umount -l "$t"; done
    rm -f $ACTIVE
}

# libbinder with a 4 MB binder buffer (the OnePlus HAL returns ~1.9 MB capture results; stock is 1 MB).
# Built from the ROM's own libbinder, rebuilt automatically when YAAP updates it. Skipped if the
# code pattern isn't found.
binder_prepare() {
    src=/system/lib64/libbinder.so
    sum=$(md5sum $src | cut -d' ' -f1)
    if [ -f $ST/libbinder.so ] && [ "$(cat $ST/libbinder.src 2>/dev/null)" = "$sum" ]; then return 0; fi
    rm -f $ST/libbinder.so $ST/libbinder.src
    out=$($MODDIR/bin/binderpatch $src $ST/libbinder.so 2>&1); rc=$?
    log I "binderpatch rc=$rc: $(echo $out)"
    [ $rc = 0 ] || { rm -f $ST/libbinder.so; return 1; }
    if [ "$(cmp -l $src $ST/libbinder.so | wc -l)" != 2 ]; then log E "patched libbinder differs by more than 2 bytes, not using it"; rm -f $ST/libbinder.so; return 1; fi
    chown 0:0 $ST/libbinder.so; chmod 0644 $ST/libbinder.so; chcon u:object_r:system_lib_file:s0 $ST/libbinder.so
    echo $sum > $ST/libbinder.src
    return 0
}

hal_cur() { is_ours "$F/hal/odm/lib64" && echo oos || echo yaap; }
hal_up() {
    for t in $HAL_TGTS; do
        [ -d "$F/hal$t" ] || continue
        is_ours "$F/hal$t" && continue
        $NS mount -t overlay -o "lowerdir=$F/hal$t:$t" opcamera "$t" || { log E "HAL overlay $t failed"; hal_down; return 1; }
    done
    # tested setup: OPlus camera's 10-bit path off (as on DerpFest, which doesn't set this prop)
    $RP -d oplus.software.camera.10bit >/dev/null 2>&1
    return 0
}
hal_down() {
    for t in $HAL_TGTS; do is_ours "$F/hal$t" && $NS umount -l "$t"; done
    v=$(cat $ST/10bit.orig 2>/dev/null); [ -n "$v" ] && $RP -n oplus.software.camera.10bit "$v"
    return 0
}

cam_busy() {   # true if some app has a camera open
    dumpsys media.camera 2>/dev/null | awk '/^Active Camera Clients:/{getline; getline; f=($0 ~ /^\(Camera ID/); exit} END{exit !f}'
}
cams_ready() { [ "$(dumpsys media.camera 2>/dev/null | grep -c '^== Camera HAL device.*static information')" -ge 6 ]; }

# Live switch between the two HALs. Restarts the camera provider + cameraserver (~6 s).
hal_switch() {
    stop cameraserver; stop vendor.camera-provider
    if [ "$1" = oos ]; then hal_up; r=$?; else hal_down; r=$?; fi
    start vendor.camera-provider; start cameraserver
    i=0; while [ $i -lt 30 ] && ! cams_ready; do sleep 0.5; i=$((i+1)); done
    return $r
}

# Lens-row position fix: a resource overlay (no code) for com.oplus.camera, preinstalled in
# /product/overlay. Not static, so it can be switched live:  echo off > /data/adb/opcamera/zoomfix
ZOOMFIX=com.syleront.opcamera.zoomfix
zoomfix_apply() {
    want=$(cat $ST/zoomfix 2>/dev/null); [ "$want" = off ] || want=on
    if [ $want = on ]; then cmd overlay enable --user 0 $ZOOMFIX >/dev/null 2>&1
    else cmd overlay disable --user 0 $ZOOMFIX >/dev/null 2>&1; fi
    log I "zoomfix $want: $(cmd overlay list com.oplus.camera 2>/dev/null | grep $ZOOMFIX)"
}

set_props() {
    $RP -n persist.vendor.camera.privapp.list $OPLUS
    $RP -n ro.oplus.system.camera.name $OPLUS
    $RP -n ro.com.google.lens.oem_camera_package $OPLUS
    $RP -n ro.com.google.lens.oem_image_package com.oneplus.gallery
    $RP -n ro.vendor.oplus.market.name "OnePlus 12"
    $RP -n ro.vendor.oplus.market.enname "OnePlus 12"
    $RP -n ro.vendor.oplus.market.watermark "OnePlus 12"
}
