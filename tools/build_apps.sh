#!/usr/bin/env bash
# Builds our small APK (no Gradle):
#   build/zoomfix/OPCameraZoomFix.apk    resource overlay fixing the zoom ring / lens row (src/zoomfix)
set -e
. "$(dirname "$0")/env.sh"
cd "$R"

# --- zoom ring / lens row overlay (not static, so it can be switched off live)
S=src/zoomfix; O=build/zoomfix
rm -rf "$O"; mkdir -p $O
"$AAPT2" compile --dir $S/res -o $O/res.zip
# --no-resource-deduping: the sw380dp value must stay (see docs/NOTES.md)
"$AAPT2" link --no-resource-deduping -o $O/unaligned.apk -I "$ANDROID_JAR" --manifest $S/AndroidManifest.xml \
    $O/res.zip --min-sdk-version 34 --target-sdk-version 36
"$ZIPALIGN" -f 4 $O/unaligned.apk $O/aligned.apk
apksign $O/aligned.apk $O/OPCameraZoomFix.apk
ls -l build/zoomfix/OPCameraZoomFix.apk
