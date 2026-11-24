#!/usr/bin/env bash
# Builds the native parts into build/native/:
#   binderpatch        on-device libbinder patcher (src/binderpatch)
#   relink             on-device DT_NEEDED renamer for the ROM's camera libraries (src/relink)
#   libapsfix.so       AHardwareBuffer_lockPlanes + offline crop fix loaded by OnePlus APS (src/apsfix)
#   libcsext_shim.so   CameraSessionStats constants for libcsextimpl.so + the OnePlus camera's
#                      characteristics filter (src/shim)
#   libheiffix.so      HEIC parameter-name fix for libAPSClient-cmd-jni.so (src/heiffix)
#   cave.bin           camera-eviction stub for tools/patch_cameraserver.py (src/evictfix)
#   charstub.bin       characteristics hooks embedded in tools/patch_cs_chars.py (src/csfix)
#   cropstub.bin       crop hook embedded in tools/patch_apscrop.py (src/apscrop)
# The stubs embedded in the patchers are checked against these builds.
set -e
. "$(dirname "$0")/env.sh"
O=$R/build/native; rm -rf "$O"; mkdir -p "$O/stub"
cd "$R"
EXE="--target=aarch64-linux-android34 -O2 -fPIE -pie -Wall -Wextra -Wl,-z,max-page-size=16384 -s"
"$CLANG" $EXE -o "$O/binderpatch" src/binderpatch/binderpatch.c
"$CLANG" $EXE -o "$O/relink" src/relink/relink.c
"$CLANG" --target=aarch64-linux-android34 -shared -fPIC -Wl,-soname,libextendfile.so \
    -o "$O/stub/libextendfile.so" src/apsfix/stub.c
"$CLANG" --target=aarch64-linux-android34 -O2 -shared -fPIC -fvisibility=hidden -o "$O/libapsfix.so" \
    -Wl,-soname,libapsfix.so -Wl,-z,max-page-size=16384 src/apsfix/apsfix.c -L"$O/stub" \
    -Wl,--no-as-needed -lextendfile -lnativewindow -llog -ldl -Wl,--as-needed
"$CLANGXX" --target=aarch64-linux-android34 -shared -fPIC -O2 -nostdlib++ -Wall -Wextra \
    -Wno-vla-cxx-extension -Wno-vla-extension -fvisibility=hidden -Wl,-soname,libcsext_shim.so \
    -Wl,--build-id=sha1 -o "$O/libcsext_shim.so" src/shim/csext_shim.cpp src/shim/charfilter.cpp -llog -ldl
"$CLANG" --target=aarch64-linux-android34 -O2 -shared -fPIC -fvisibility=hidden -Wall -Wextra -Wl,-soname,libheiffix.so \
    -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 -s -o "$O/libheiffix.so" src/heiffix/heiffix.c -llog

# position-dependent stubs (addresses: the tested cameraserver / libAlgoProcess.so, see the patchers)
stub() { # name src text-addr ld-args...
    n=$1 s=$2 a=$3; shift 3
    "$CLANG" --target=aarch64-linux-android30 -c "$s" -o "$O/$n.o"
    "$NDKBIN/ld.lld$X" -o "$O/$n.elf" "$O/$n.o" -Ttext=$a -z noseparate-code "$@"
    "$NDKBIN/llvm-objcopy$X" -O binary --only-section=.text "$O/$n.elf" "$O/$n.bin"
}
stub cave src/evictfix/cave.s 0x37eee0 --defsym=isPriv=0xf5ca4 --defsym=wouldEvict=0xf620c -e cave
stub charstub src/csfix/charstub.s 0x37ef40 --defsym=dlopen=0x37e1c0 --defsym=dlsym=0x37e1e0 \
    --defsym=atrace_get_enabled_tags=0x37bbd0 -e charenter
stub cropstub src/apscrop/cropstub.s 0x70d3c0 --defsym=lockPlaneX=0x700220 --defsym=setMetadata=0x6fdc88 -e cropstub
hexof() { od -An -tx1 -v "$1" | tr -d ' \n'; }
embedded() { sed -n "/^$2 = bytes.fromhex(/,/)/p" "$1" | grep -o "'[0-9a-f]*'" | tr -d "'\n"; }
[ "$(hexof "$O/cave.bin")" = "$(embedded tools/patch_cameraserver.py CAVE_CODE)" ] || die "cave.bin differs from tools/patch_cameraserver.py"
[ "$(hexof "$O/charstub.bin")" = "$(embedded tools/patch_cs_chars.py STUB)" ] || die "charstub.bin differs from tools/patch_cs_chars.py"
[ "$(hexof "$O/cropstub.bin")" = "$(embedded tools/patch_apscrop.py STUB)" ] || die "cropstub.bin differs from tools/patch_apscrop.py"
rm -f "$O"/*.o "$O"/*.elf
ls -l "$O"; md5sum "$O"/*.so "$O"/binderpatch "$O"/relink
