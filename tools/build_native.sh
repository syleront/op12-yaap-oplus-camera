#!/usr/bin/env bash
# Builds the native parts into build/native/:
#   binderpatch        on-device libbinder patcher (src/binderpatch)
#   libapsfix.so       AHardwareBuffer_lockPlanes fix loaded by OnePlus APS (src/apsfix)
#   libcsext_shim.so   CameraSessionStats constants for libcsextimpl.so (src/shim)
#   cave.bin           camera-eviction stub for tools/patch_cameraserver.py (src/evictfix)
set -e
. "$(dirname "$0")/env.sh"
O=$R/build/native; rm -rf "$O"; mkdir -p "$O/stub"
cd "$R"
"$CLANG" --target=aarch64-linux-android34 -O2 -fPIE -pie -Wall -Wextra -Wl,-z,max-page-size=16384 -s \
    -o "$O/binderpatch" src/binderpatch/binderpatch.c
"$CLANG" --target=aarch64-linux-android34 -shared -fPIC -Wl,-soname,libextendfile.so \
    -o "$O/stub/libextendfile.so" src/apsfix/stub.c
"$CLANG" --target=aarch64-linux-android34 -O2 -shared -fPIC -fvisibility=hidden -o "$O/libapsfix.so" \
    -Wl,-soname,libapsfix.so -Wl,-z,max-page-size=16384 src/apsfix/apsfix.c -L"$O/stub" \
    -Wl,--no-as-needed -lextendfile -lnativewindow -llog -Wl,--as-needed
"$CLANGXX" --target=aarch64-linux-android34 -shared -fPIC -O2 -nostdlib++ -Wl,-soname,libcsext_shim.so \
    -Wl,--build-id=sha1 -o "$O/libcsext_shim.so" src/shim/csext_shim.cpp
# addresses are those of the tested DerpFest cameraserver (see tools/patch_cameraserver.py)
"$CLANG" --target=aarch64-linux-android30 -c src/evictfix/cave.s -o "$O/cave.o"
"$NDKBIN/ld.lld$X" -o "$O/cave.elf" "$O/cave.o" -Ttext=0x37eee0 --defsym=isPriv=0xf5ca4 \
    --defsym=wouldEvict=0xf620c -e cave -z noseparate-code
"$NDKBIN/llvm-objcopy$X" -O binary --only-section=.text "$O/cave.elf" "$O/cave.bin"
ls -l "$O"
