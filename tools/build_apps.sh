#!/usr/bin/env bash
# Builds our two small APKs (no Gradle):
#   build/halswitch/HalSwitch.apk        "Camera HAL" quick settings tile + launcher icon (src/halswitch)
#   build/zoomfix/OPCameraZoomFix.apk    resource overlay fixing the zoom ring / lens row (src/zoomfix)
set -e
. "$(dirname "$0")/env.sh"
cd "$R"

# --- HalSwitch
S=src/halswitch; O=build/halswitch
rm -rf "$O"; mkdir -p $O/gen $O/classes $O/dex
"$AAPT2" compile --dir $S/res -o $O/res.zip
"$AAPT2" link -o $O/base.apk -I "$ANDROID_JAR" --manifest $S/AndroidManifest.xml $O/res.zip \
    --min-sdk-version 34 --target-sdk-version 36 --java $O/gen
"$JAVAC" -encoding UTF-8 -source 8 -target 8 -Xlint:-options -nowarn -bootclasspath "$ANDROID_JAR" -d $O/classes \
    $(find $S/java $O/gen -name '*.java')
"$D8" --release --min-api 34 --lib "$ANDROID_JAR" --output $O/dex $(find $O/classes -name '*.class')
py "$(hp "$R/tools/zipadd.py")" "$(hp "$R/$O/base.apk")" "$(hp "$R/$O/dex/classes.dex")" classes.dex
"$ZIPALIGN" -f 4 $O/base.apk $O/aligned.apk
apksign $O/aligned.apk $O/HalSwitch.apk

# --- zoom ring / lens row overlay (not static, so it can be switched off live)
S=src/zoomfix; O=build/zoomfix
rm -rf "$O"; mkdir -p $O
"$AAPT2" compile --dir $S/res -o $O/res.zip
# --no-resource-deduping: the sw380dp value must stay (see docs/NOTES.md)
"$AAPT2" link --no-resource-deduping -o $O/unaligned.apk -I "$ANDROID_JAR" --manifest $S/AndroidManifest.xml \
    $O/res.zip --min-sdk-version 34 --target-sdk-version 36
"$ZIPALIGN" -f 4 $O/unaligned.apk $O/aligned.apk
apksign $O/aligned.apk $O/OPCameraZoomFix.apk
ls -l build/halswitch/HalSwitch.apk build/zoomfix/OPCameraZoomFix.apk
