# Shared by all module scripts. The caller sets MODDIR. Works with KernelSU (and forks), Magisk and APatch.
# Nothing in this module is mounted by the root manager itself (no system/ dir): every mount is done
# here, in init's mount namespace, and is gone after a reboot.

ST=/data/adb/opcamera                 # state kept across module updates
LOG=$ST/log.txt
# Module files. Used in place, except on kernels that refuse /data folders as overlay layers
# ("overlayfs: filesystem on ... not supported", seen on crDroid): there customize.sh packs them into
# an ext4 image, loop-mounted read-only at boot (what KernelSU's meta-overlayfs does for all modules).
IMG=$MODDIR/files.img
IMG_MNT=/dev/opcamera.files
F=$MODDIR/files; [ -f $IMG ] && F=$IMG_MNT
NS="nsenter -t 1 -m --"
RP=resetprop
for p in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop; do [ -x $p ] && { RP=$p; break; }; done
[ $RP = resetprop ] && ! command -v resetprop >/dev/null 2>&1 && command -v magisk >/dev/null 2>&1 && RP="magisk resetprop"
ACTIVE=/dev/opcamera.active           # tmpfs marker: our mounts are up this boot
LOCK=/dev/opcamera.lock
OPLUS=com.oplus.camera
EXPECT_SDK=37

# Overlay targets. sys = cameraserver stack + OPlus camera app (always on while the module is active)
SYS_TGTS="/system/lib64 /system_ext/lib64 /system_ext/priv-app /system_ext/app /system_ext/framework /system_ext/etc/permissions /system_ext/etc/default-permissions /system_ext/etc/sysconfig /product/overlay"
OPT_TGTS="/product/overlay"     # optional: skipped (not fatal) if missing
# hal = what the OnePlus camera needs on top of the ROM's own camera HAL (YAAP ships OnePlus's camera
# blobs): libOplusSecurity.so, which the ROM lacks; libus.so = DerpFest's libui-stock.so (see RELINK); and
# the camera app's own processing libraries, configs and licences (libAlgoProcess & co. run in the app).
# Our odm/etc files are all in camera/: overlay only that folder when the ROM has it, so audio mods etc.
# in /odm/etc aren't affected.
HAL_TGTS="/odm/lib64 /odm/etc /vendor/lib64"
[ -d /odm/etc/camera ] && HAL_TGTS="/odm/lib64 /odm/etc/camera /vendor/lib64"
# The ROM's OnePlus HAL libraries built against OnePlus's libui: with AOSP's libui.so their
# GraphicBuffers don't match and the camera provider's heap gets corrupted. Relinked at boot from the
# ROM's own files to libus.so (bin/relink, src/relink), cached in $RL, bind-mounted over the originals.
RELINK="/odm/lib64/camera/components/com.oplus.node.mvgsat.so /odm/lib64/camera/components/com.oplus.node.sstabphoto.so
/odm/lib64/hw/camera.oemlayer.so /odm/lib64/libEIS.so /odm/lib64/libEISLive.so /odm/lib64/libHIS.so
/odm/lib64/libmvgcommon.so /odm/lib64/libsharebuffer_impl.so /vendor/lib64/camera/components/com.qti.node.dewarp.so"
RL=$ST/relink
# The camera app's config (camera unit SDK, read only by the OnePlus camera): a copy of the ROM's with
# a few values overridden for YAAP's HAL, made at boot ($UCF) and bind-mounted over the original.
# - the 65:24 "wide" photo ratio is hidden (the HAL has no such sizes; the camera stayed black);
# - photo-mode preview sizes (live photo lists, index = ratio: 1:1, 4:3, 16:9, full, ...): YAAP's HAL has
#   none of 1440x1440, 2136x1200, 2640x1200, 1296x1296, 1728x1296, 2384x1080, so 1:1, 16:9 and Full froze
#   the camera; replaced by the HAL's sizes of the same ratio.
UC=/odm/etc/camera/config/camera_unit_config
UCF=$ST/camera_unit_config
UC_ADD='    "com.oplus.camera.wide.frame.ratio.support.modelist":"",
    "com.oplus.camera.livephoto.pre.full.size.configure":"2376x1080",
    "com.oplus.feature.capture.mode.livephoto.size":"1200x1200x1920x1440x1920x1080x2376x1080x1080x1080x1440x1080x1920x1080x2376x1080x0x0x0x0x0x0x0x0x2136x788x1920x708",
    "com.oplus.feature.capture.mode.livephoto.front.size":"1200x1200x1920x1440x1920x1080x2376x1080x1080x1080x1440x1080x1920x1080x2376x1080",'
# The HAL's own config: a copy of the ROM's, made at boot ($HCF) and bind-mounted over the original, with
# one line changed: isEnableVIULL = FALSE. The video "ultra low light" path (MultiCameraSATVIULL pipeline,
# normal video at 30 fps in low light) outputs frames without colour (green) on YAAP's HAL.
HC=/odm/etc/camera/CameraHWConfiguration.config
HCF=$ST/CameraHWConfiguration.config

log() { echo "$(date '+%m-%d %H:%M:%S') [$1] $2" >> $LOG; }
trim_log() { [ -f $LOG ] && [ $(wc -l < $LOG) -gt 400 ] && { tail -n 200 $LOG > $LOG.tmp; mv $LOG.tmp $LOG; }; }

# Replace the description line. No sed: the text is free-form and must not be parsed as a pattern
# (a "|" in it once wiped module.prop). Text goes through ENVIRON so awk doesn't interpret escapes.
set_desc() {
    p=$MODDIR/module.prop
    grep -q '^id=' $p || return 1
    DESC="$1" awk '/^description=/ { print "description=" ENVIRON["DESC"]; done = 1; next } { print }
        END { if (!done) print "description=" ENVIRON["DESC"] }' $p > $p.tmp &&
        grep -q '^id=' $p.tmp && cat $p.tmp > $p
    rm -f $p.tmp
}
# ROM: YAAP (the tested one) or, experimentally, any other custom ROM on the OnePlus 12 (waffle).
is_waffle() {
    [ "$(getprop ro.lineage.device)" = waffle ] && return 0
    for p in ro.product.device ro.build.product ro.product.vendor.device ro.product.odm.device \
             ro.product.product.device ro.product.system.device ro.product.system_ext.device; do
        case "$(getprop $p)" in waffle|OP595DL1|OP5929L1) return 0 ;; esac
    done
    return 1
}
# Stock OxygenOS/ColorOS (KernelSU works there too): has its own OnePlus camera, never mount over it
is_oplus_stock() { [ -n "$(getprop ro.build.version.oplusrom)" ] || [ -d /my_product ]; }
# Any custom ROM on waffle is accepted (they share the same device tree); YAAP is the tested one.
# The id/name is only a label (HAL name in the tile, log): yaap | crdroid | lineage | other
rom_id() {
    case "$(getprop ro.build.fingerprint)" in */yaap_waffle/waffle:*) echo yaap; return ;; esac
    if [ -n "$(getprop ro.crdroid.version)$(getprop ro.crdroid.build.version)$(getprop ro.crdroid.display.version)" ]; then
        echo crdroid; return
    fi
    [ -n "$(getprop ro.lineage.version)$(getprop ro.lineage.build.version)$(getprop ro.lineage.device)" ] && { echo lineage; return; }
    case "$(getprop ro.modversion)" in *[Cc][Rr][Dd]roid*) echo crdroid ;; *[Ll]ineage*) echo lineage ;; *) echo other ;; esac
}
rom_name() { case "$(rom_id)" in yaap) echo YAAP ;; crdroid) echo crDroid ;; lineage) echo LineageOS ;; *) echo ROM ;; esac; }
rom_info() {   # one line for logs and install errors
    echo "fingerprint=$(getprop ro.build.fingerprint) sdk=$(getprop ro.build.version.sdk)" \
         "modversion=$(getprop ro.modversion) lineage=$(getprop ro.lineage.version)/$(getprop ro.lineage.build.version)" \
         "lineage.device=$(getprop ro.lineage.device) crdroid=$(getprop ro.crdroid.version)/$(getprop ro.crdroid.build.version)" \
         "device=$(getprop ro.product.device)/$(getprop ro.product.vendor.device)/$(getprop ro.build.product)/$(getprop ro.product.odm.device)" \
         "platform=$(getprop ro.board.platform) prj=$(getprop ro.boot.prjname)"
}

desc_active() {
    r=$(rom_name); x=; [ "$(rom_id)" = yaap ] || x=" [$r: experimental]"
    set_desc "Active: OnePlus camera on the $r camera HAL.$x"
}

# Returns a reason on stdout and fails if this ROM/device is not what the module was built for.
preflight() {
    sdk=$(getprop ro.build.version.sdk)
    [ "$sdk" = "$EXPECT_SDK" ] || { echo "Android SDK $sdk, module is for SDK $EXPECT_SDK (Android 17)"; return 1; }
    is_waffle || { echo "not a OnePlus 12 (waffle)"; return 1; }
    is_oplus_stock && { echo "this is OxygenOS/ColorOS, it already has the OnePlus camera"; return 1; }
    [ -f $IMG ] || [ -f $F/sys/system/bin/cameraserver ] || { echo "module files missing, reinstall"; return 1; }
    # the OnePlus camera needs the ROM to use OnePlus's own camera HAL blobs (YAAP does)
    [ -f /odm/lib64/hw/camera.oemlayer.so ] || { echo "this ROM doesn't use OnePlus's camera HAL (no camera.oemlayer.so)"; return 1; }
    return 0
}

# SELinux labels: copied from the live-tested setup (files/labels.txt); anything unlisted gets
# the label of the real path it shadows (or of its nearest existing parent).
apply_labels() {
    chown -R 0:0 $F
    find $F -type d -exec chmod 0755 {} +
    find $F -type f -exec chmod 0644 {} +
    chmod 0755 $F/sys/system/bin/cameraserver $MODDIR/bin/binderpatch $MODDIR/bin/relink
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

is_ours() { grep -q "lowerdir=$1:" /proc/1/mountinfo; }   # mounted at all (maybe hidden)

# State of our overlay (lower dir $1) on target $2, from init's mountinfo:
#   visible  it is what $2 shows
#   covered  another mount sits directly on top of it at $2 (e.g. another module mounted there later)
#   hidden   still mounted but unreachable: something was mounted over a parent dir (e.g. a module
#            manager's overlay on the whole partition). Module managers then usually bind a copy of ours
#            on top, which is "visible"; the hidden original is harmless and stays until reboot.
#   (empty)  not mounted
our_state() {
    awk -v low="lowerdir=$1:" -v t="$2" '
    function vis(k,  n, p) {   # no covered mount on the way up (a stack on the parent itself is fine)
        for (n = 0; n < 64; n++) { p = par[k]; if (!(p in mp)) return 1; if (mp[p] != mp[k] && (p in cov)) return 0; k = p }
        return 0
    }
    { par[$1] = $2; mp[$1] = $5; if (index($0, low)) mine[$1] = 1 }
    END {
        for (k in mp) if ((par[k] in mp) && mp[par[k]] == mp[k]) cov[par[k]] = 1
        st = ""
        for (k in mine) if (mp[k] == t) {
            if (!vis(k)) { if (st == "") st = "hidden"; continue }
            if (!(k in cov)) { st = "visible"; break }
            st = "covered"
        }
        if (st != "") print st
    }' /proc/1/mountinfo
}
# For the log when a mount/umount goes wrong: what is mounted at $1 and above, overlayfs kernel messages
mnt_diag() {
    for m in "$1" "${1%/*}" /; do
        [ -n "$m" ] || continue
        log I "  mounts at $m: $(awk -v t="$m" '$5 == t { for (i = 7; i <= NF; i++) if ($i == "-") break
            printf "[%s<-%s %s %s %s] ", $1, $2, $(i+1), $(i+2), substr($(i+3), 1, 160) }' /proc/1/mountinfo)"
    done
    log I "  module files on: $(awk -v f="$F/" '{ for (i = 7; i <= NF; i++) if ($i == "-") break }
        index(f, ($5 == "/" ? "/" : $5 "/")) == 1 && length($5) >= best { best = length($5); r = $5 " " $(i+1) " " $(i+2) " " $(i+3) }
        END { print r }' /proc/1/mountinfo)"
    log I "  dmesg: $(dmesg 2>/dev/null | grep -i overlay | tail -n 4 | tr '\n' ' ')"
}

# Can the kernel use the module files ($1, on /data) as an overlay layer? (install time)
overlay_ok() {
    d=${TMPDIR:-/dev/tmp}/opcamera_ovtest; mkdir -p $d
    if mount -t overlay -o "lowerdir=$1/hal/odm/etc:/odm/etc" opcamera_test $d 2>/dev/null; then
        umount $d; rmdir $d; return 0
    fi
    rmdir $d; return 1
}
# Loop-mount ext4 image $1 on $2 with options $3: toybox's mount -o loop, else losetup + mount.
# On failure LOOP_ERR says why (both errors + kernel messages).
loop_mount() {
    e1=$(/system/bin/mount -t ext4 -o loop,$3 $1 $2 2>&1) && return 0
    e2="losetup failed"; d=$(losetup -f 2>/dev/null)
    if [ -n "$d" ] && e2=$(losetup $d $1 2>&1); then
        e2=$(mount -t ext4 -o $3 $d $2 2>&1) && return 0
        losetup -d $d 2>/dev/null
    fi
    LOOP_ERR="mount: $e1 | losetup $d: $e2 | dmesg: $(dmesg 2>/dev/null |
        grep -iE 'loop|ext4|I/O error|avc: denied' | tail -n 8 | tr '\n' ' ')"
    return 1
}
# Pack $F into an ext4 image $IMG with the SELinux labels applied (install time). Uses Android's mke2fs.
# IMG_ERR says why on failure.
img_build() {
    m=${TMPDIR:-/dev/tmp}/opcamera_img
    mb=$(( $(du -sm $F | cut -f1) * 110 / 100 + 64 ))
    rm -f $IMG
    out=$(truncate -s ${mb}M $IMG 2>&1 && /system/bin/mke2fs -t ext4 -F -m 0 -O ^has_journal -L opcamera $IMG 2>&1) ||
        { IMG_ERR="mke2fs: $(echo "$out" | tail -n 3 | tr '\n' ' ')"; rm -f $IMG; return 1; }
    # the loop driver reads the image as the kernel on some kernels: label it as a system file and
    # allow that (sepolicy.rule does the same at boot)
    chcon u:object_r:system_file:s0 $IMG 2>/dev/null
    for c in "magiskpolicy --live" "ksud sepolicy patch"; do
        command -v ${c%% *} >/dev/null 2>&1 && $c "allow kernel system_file file { read getattr open }" >/dev/null 2>&1 && break
    done
    mkdir -p $m
    loop_mount $IMG $m rw,noatime || { IMG_ERR=$LOOP_ERR; rmdir $m; rm -f $IMG; return 1; }
    ok=0
    if cp -a $F/. $m/; then
        rm -rf $m/lost+found; chcon u:object_r:system_file:s0 $m
        src=$F; F=$m; apply_labels && labels_ok && ok=1; F=$src
    else IMG_ERR="copying the files failed (not enough free space?)"; fi
    [ $ok = 1 ] || [ -n "$IMG_ERR" ] || IMG_ERR="setting SELinux labels in the image failed"
    umount $m; rmdir $m
    [ $ok = 1 ] || { rm -f $IMG; return 1; }
    return 0
}
# Loop-mount the image read-only at $IMG_MNT (boot). Not nosuid: cameraserver is bound from it.
img_mount() {
    awk -v m=$IMG_MNT '$5 == m { f = 1 } END { exit !f }' /proc/1/mountinfo && return 0
    mkdir -p $IMG_MNT
    loop_mount $IMG $IMG_MNT ro,noatime || { log E "image mount failed: $LOOP_ERR"; return 1; }
    return 0
}

mount_sys() {
    for t in $SYS_TGTS; do
        [ -d "$F/sys$t" ] || continue
        if [ ! -d "$t" ]; then
            case " $OPT_TGTS " in *" $t "*) log W "optional target $t missing, skipped"; continue ;; esac
            log E "target $t does not exist"; return 1
        fi
        err=$($NS mount -t overlay -o "lowerdir=$F/sys$t:$t" opcamera "$t" 2>&1) ||
            { log E "overlay $t failed: $err"; mnt_diag "$t"; return 1; }
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
# Built from the ROM's own libbinder, rebuilt automatically when the ROM updates it. Skipped if the
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

# Relinked copies of the ROM's libraries listed in RELINK, in $RL. Redone when the ROM's files (or the
# tool) change. A library that doesn't use libui.so is left as it is; any other problem -> fails, $RL removed.
relink_key() { for f in $MODDIR/bin/relink $RELINK; do if [ -f $f ]; then md5sum $f; else echo "- $f"; fi; done; }
relink_prepare() {
    k=$(relink_key)
    [ -d $RL ] && [ "$(cat $RL.key 2>/dev/null)" = "$k" ] && return 0
    rm -rf $RL $RL.key; mkdir -p $RL
    n=0
    for f in $RELINK; do
        [ -f $f ] || { log W "relink: $f is not in this ROM, skipped"; continue; }
        mkdir -p $RL${f%/*}
        out=$($MODDIR/bin/relink $f $RL$f libui.so libus.so 2>&1); rc=$?
        case $rc in
            # (not stat -c %C: the root managers run this with busybox, whose stat has no %C)
            0) lbl=$(ls -dZ $f | awk '{print $1}')
               chown 0:0 $RL$f; chmod 0644 $RL$f
               case "$lbl" in u:object_r:*) ;; *) log E "relink: no SELinux label for $f ($lbl)"; rm -rf $RL; return 1 ;; esac
               chcon "$lbl" $RL$f || { log E "relink: chcon $lbl $f failed"; rm -rf $RL; return 1; }
               n=$((n+1)) ;;
            2) log I "relink: $f doesn't use libui.so, left as it is" ;;
            *) log E "relink: $f failed (rc=$rc): $out"; rm -rf $RL; return 1 ;;
        esac
    done
    echo "$k" > $RL.key
    log I "relinked $n ROM camera libraries to libus.so"
    return 0
}
relink_mounted() {   # $1 = target path; true if our relinked copy is bind-mounted there
    awk -v t="$1" -v s="/opcamera/relink$1" '$5 == t && index($4, s) { f = 1 } END { exit !f }' /proc/1/mountinfo
}

# $UCF = the ROM's $UC with the UC_ADD lines inserted at the top of "vendor_tag_type_values". Redone when
# the ROM's file or the module changes. Not fatal: without it only some photo ratios don't work.
unitcfg_prepare() {
    [ -f $UC ] || { log W "unitcfg: $UC is not in this ROM"; return 1; }
    k=$(md5sum $UC $MODDIR/common.sh | cut -d' ' -f1 | tr '\n' ' ')
    [ -f $UCF ] && [ "$(cat $UCF.key 2>/dev/null)" = "$k" ] && return 0
    rm -f $UCF $UCF.key
    if [ "$(grep -cE '^[[:space:]]*"vendor_tag_type_values"[[:space:]]*:[[:space:]]*[{][[:space:]]*$' $UC)" != 1 ]; then
        log W "unitcfg: unexpected $UC (no \"vendor_tag_type_values\":{ line), left as it is"; return 1
    fi
    for key in $(echo "$UC_ADD" | cut -d'"' -f2); do
        grep -q "\"$key\"" $UC && { log W "unitcfg: the ROM already sets $key, left as it is"; return 1; }
    done
    ADD="$UC_ADD" awk '{ print } /^[[:space:]]*"vendor_tag_type_values"[[:space:]]*:[[:space:]]*[{][[:space:]]*$/ { print ENVIRON["ADD"] }' \
        $UC > $UCF.tmp
    n=$(echo "$UC_ADD" | wc -l)
    if [ "$(wc -l < $UCF.tmp)" != "$(( $(wc -l < $UC) + n ))" ]; then
        log E "unitcfg: generated file has the wrong size"; rm -f $UCF.tmp; return 1
    fi
    lbl=$(ls -dZ $UC | awk '{print $1}')
    case "$lbl" in u:object_r:*) ;; *) log E "unitcfg: no SELinux label for $UC ($lbl)"; rm -f $UCF.tmp; return 1 ;; esac
    chown 0:0 $UCF.tmp; chmod 0644 $UCF.tmp
    chcon "$lbl" $UCF.tmp || { log E "unitcfg: chcon $lbl failed"; rm -f $UCF.tmp; return 1; }
    mv $UCF.tmp $UCF && echo "$k" > $UCF.key
    log I "unitcfg: camera config prepared ($n values)"
    return 0
}
unitcfg_mounted() { awk -v t="$UC" '$5 == t && index($4, "/opcamera/camera_unit_config") { f = 1 } END { exit !f }' /proc/1/mountinfo; }

# $HCF = the ROM's $HC with the line above changed. Refuses unless exactly one line matches. Not fatal:
# without it only normal video at 30 fps in low light is affected.
hwcfg_prepare() {
    [ -f $HC ] || { log W "hwcfg: $HC is not in this ROM"; return 1; }
    k=$(md5sum $HC $MODDIR/common.sh | cut -d' ' -f1 | tr '\n' ' ')
    [ -f $HCF ] && [ "$(cat $HCF.key 2>/dev/null)" = "$k" ] && return 0
    rm -f $HCF $HCF.key
    awk '/^[[:space:]]*isEnableVIULL[[:space:]]*=[[:space:]]*TRUE[[:space:]]*$/ { sub(/TRUE/, "FALSE"); v++ }
         { print }
         END { exit v != 1 }' $HC > $HCF.tmp ||
        { log W "hwcfg: unexpected $HC (not exactly one \"isEnableVIULL = TRUE\" line), left as it is"; rm -f $HCF.tmp; return 1; }
    if [ "$(wc -l < $HCF.tmp)" != "$(wc -l < $HC)" ] ||
       [ "$(awk 'NR == FNR { a[FNR] = $0; next } a[FNR] != $0 { c++ } END { print c + 0 }' $HC $HCF.tmp)" != 1 ]; then
        log E "hwcfg: generated file differs in more than 1 line"; rm -f $HCF.tmp; return 1
    fi
    lbl=$(ls -dZ $HC | awk '{print $1}')
    case "$lbl" in u:object_r:*) ;; *) log E "hwcfg: no SELinux label for $HC ($lbl)"; rm -f $HCF.tmp; return 1 ;; esac
    chown 0:0 $HCF.tmp; chmod 0644 $HCF.tmp
    chcon "$lbl" $HCF.tmp || { log E "hwcfg: chcon $lbl failed"; rm -f $HCF.tmp; return 1; }
    mv $HCF.tmp $HCF && echo "$k" > $HCF.key
    log I "hwcfg: HAL config prepared (no video low-light path)"
    return 0
}
hwcfg_mounted() { awk -v t="$HC" '$5 == t && index($4, "/opcamera/CameraHWConfiguration.config") { f = 1 } END { exit !f }' /proc/1/mountinfo; }

# "covered" counts as ours: whatever sits on top was mounted over our files and normally still shows them
hal_on() { case "$(our_state "$F/hal/odm/lib64" /odm/lib64)" in visible|covered) return 0 ;; *) return 1 ;; esac; }
hal_up() {
    for t in $HAL_TGTS; do
        [ -d "$F/hal$t" ] || continue
        case "$(our_state "$F/hal$t" "$t")" in visible|covered) continue ;; esac
        err=$($NS mount -t overlay -o "lowerdir=$F/hal$t:$t" opcamera "$t" 2>&1) &&
            [ "$(our_state "$F/hal$t" "$t")" = visible ] ||
            { log E "HAL overlay $t failed: $err"; mnt_diag "$t"; hal_down; return 1; }
    done
    for f in $RELINK; do
        [ -f $RL$f ] || continue
        relink_mounted $f && continue
        err=$($NS mount -o bind $RL$f $f 2>&1) || { log E "bind $f failed: $err"; mnt_diag "${f%/*}"; hal_down; return 1; }
    done
    if [ -f $UCF ] && [ -f $UC ] && ! unitcfg_mounted; then
        err=$($NS mount -o bind $UCF $UC 2>&1) || log W "bind $UC failed (some photo ratios won't work): $err"
    fi
    if [ -f $HCF ] && [ -f $HC ] && ! hwcfg_mounted; then
        err=$($NS mount -o bind $HCF $HC 2>&1) || log W "bind $HC failed (video may flash green in low light): $err"
    fi
    return 0
}
# Unmounts only our own visible overlays (several copies of ours stacked: all of them). Fails if ours is
# covered by another mount: removing that one would break whatever mounted it.
hal_down() {
    r=0
    n=0; while [ $n -lt 3 ] && unitcfg_mounted; do $NS umount -l $UC; n=$((n+1)); done
    n=0; while [ $n -lt 3 ] && hwcfg_mounted; do $NS umount -l $HC; n=$((n+1)); done
    for f in $RELINK; do n=0; while [ $n -lt 3 ] && relink_mounted $f; do $NS umount -l $f; n=$((n+1)); done; done
    for t in $HAL_TGTS; do
        n=0
        while [ $n -lt 3 ] && [ "$(our_state "$F/hal$t" "$t")" = visible ]; do
            err=$($NS umount -l "$t" 2>&1) || log W "umount $t: $err"
            n=$((n+1))
        done
        case "$(our_state "$F/hal$t" "$t")" in
            visible) log E "could not unmount $t"; mnt_diag "$t"; r=1 ;;
            covered) log E "$t: another mount sits on top of ours (another module?), left alone"; mnt_diag "$t"; r=1 ;;
        esac
    done
    return $r
}
# After boot, for the log: which of our overlays something else has stacked on or replaced
mounts_report() {
    for k in sys hal; do
        for t in $SYS_TGTS $HAL_TGTS; do
            [ -d "$F/$k$t" ] || continue
            s=$(our_state "$F/$k$t" "$t")
            [ -z "$s" ] || [ "$s" = visible ] || { log W "$t: our overlay is $s"; mnt_diag "$t"; }
        done
    done
}

cams_count() { dumpsys media.camera 2>/dev/null | grep -c '^== Camera HAL device.*static information'; }
cams_ready() { [ "$(cams_count)" -ge 6 ]; }

# init service of the camera provider (from the vendor's .rc; vendor.camera-provider on YAAP)
cam_provider() {
    s=$(cat /vendor/etc/init/*.rc /odm/etc/init/*.rc 2>/dev/null |
        awk '$1 == "service" && $3 ~ /camera\.provider/ { print $2; exit }')
    echo ${s:-vendor.camera-provider}
}

# Zoom ring + lens-row fix: a resource overlay (no code) for com.oplus.camera, preinstalled in
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
