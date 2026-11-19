#!/usr/bin/env bash
# Fills payload/ with the DerpFest files listed in payload/MANIFEST.sha256 (Linux or WSL).
#
#   tools/extract_payload.sh <DerpFest ROM .zip | dir with system.img system_ext.img odm.img vendor.img>
#
# Needs debugfs (e2fsprogs) and fsck.erofs (erofs-utils); for a ROM zip also payload-dumper-go
# (https://github.com/ssut/payload-dumper-go) in PATH. Needs DerpFest-v17 waffle 20261005: the camera
# service patch is made for its cameraserver (20261115 has the same camera files apart from that).
#
# OplusCamera.apk comes out stock; run tools/repack_camera_apk.sh on it afterwards (see docs/PAYLOAD.md).
set -e
die() { echo "error: $*" >&2; exit 1; }
[ $# = 1 ] || die "usage: $0 <DerpFest ROM .zip | images dir>"
R=$(cd "$(dirname "$0")/.." && pwd); P=$R/payload; M=$P/MANIFEST.sha256
command -v debugfs >/dev/null || die "debugfs not found (apt install e2fsprogs)"
command -v fsck.erofs >/dev/null || die "fsck.erofs not found (apt install erofs-utils)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

if [ -f "$1" ]; then
    command -v payload-dumper-go >/dev/null || die "payload-dumper-go not found (or pass a dir with the .img files)"
    echo "- unpacking system, system_ext, odm, vendor from $1"
    payload-dumper-go -q -p system,system_ext,odm,vendor -o "$T/img" "$1" >/dev/null
    IMG=$T/img
else
    IMG=$1
fi
for p in system system_ext odm vendor; do [ -f "$IMG/$p.img" ] || die "missing $IMG/$p.img"; done

fstype() { # ext4 or erofs
    if [ "$(od -An -tx1 -j1080 -N2 "$1" | tr -d ' ')" = 53ef ]; then echo ext4
    elif [ "$(od -An -tx1 -j1024 -N4 "$1" | tr -d ' ')" = e2e1f5e0 ]; then echo erofs
    else die "unknown filesystem in $1"; fi
}
declare -A EROFS
get() { # <partition> <path in image> <dest>
    local img=$IMG/$1.img
    mkdir -p "$(dirname "$3")"
    if [ "$(fstype "$img")" = ext4 ]; then
        debugfs -R "dump \"$2\" \"$3\"" "$img" >/dev/null 2>&1
    else
        if [ -z "${EROFS[$1]}" ]; then
            echo "- extracting $1.img (erofs)"
            mkdir -p "$T/$1"; fsck.erofs --extract="$T/$1" --no-preserve "$img" >/dev/null
            EROFS[$1]=1
        fi
        cp "$T/$1$2" "$3" 2>/dev/null || true
    fi
    [ -s "$3" ] || die "$2 not found in $1.img"
}

echo "- copying $(grep -c . "$M") files"
while read -r _ f; do
    case $f in
        # DerpFest has it in /system/framework; the module provides it from /system_ext (oplus_fwk_library.xml)
        sys/system_ext/framework/oplus-fwk.jar) get system "/system/framework/oplus-fwk.jar" "$P/$f" ;;
        sys/system/*)    get system     "/system/${f#sys/system/}"   "$P/$f" ;;
        sys/system_ext/*) get system_ext "/${f#sys/system_ext/}"      "$P/$f" ;;
        hal/odm/*)        get odm        "/${f#hal/odm/}"             "$P/$f" ;;
        hal/vendor/*)     get vendor     "/${f#hal/vendor/}"          "$P/$f" ;;
        *) die "unexpected manifest path $f" ;;
    esac
done < "$M"

APK=sys/system_ext/priv-app/OplusCamera/OplusCamera.apk
bad=$(cd "$P" && sha256sum -c MANIFEST.sha256 2>/dev/null | grep -v ': OK$' | grep -v "^$APK: FAILED$" || true)
[ -z "$bad" ] || die "these files differ from the tested ones (other DerpFest build?):
$bad"
echo "- all files match payload/MANIFEST.sha256 (except $APK, which is still stock)"
echo "  next: tools/repack_camera_apk.sh payload/$APK payload/$APK"
