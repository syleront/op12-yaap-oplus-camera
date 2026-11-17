#!/bin/sh
# Builds build/halswitch/HalSwitch.apk (quick settings tile + launcher shortcut) without Gradle.
set -e
cd "$(dirname "$0")/.."
SDK=/c/Users/Syleront/AppData/Local/Android/Sdk; B=$SDK/build-tools/36.0.0; P=$SDK/platforms/android-36/android.jar
export JAVA_HOME='C:\Users\Syleront\.jdks\temurin-17.0.20'; J="/c/Users/Syleront/.jdks/temurin-17.0.20/bin"
S=src/halswitch; O=build/halswitch
rm -rf "${O:?}"; mkdir -p $O/gen $O/classes $O/dex
$B/aapt2.exe compile --dir $S/res -o $O/res.zip
$B/aapt2.exe link -o $O/base.apk -I $P --manifest $S/AndroidManifest.xml $O/res.zip \
    --min-sdk-version 34 --target-sdk-version 36 --java $O/gen
"$J/javac.exe" -encoding UTF-8 -source 8 -target 8 -Xlint:-options -bootclasspath $P -d $O/classes \
    $(find $S/java $O/gen -name '*.java')
$B/d8.bat --release --min-api 34 --lib $P --output $O/dex $(find $O/classes -name '*.class')
MSYS_NO_PATHCONV=1 wsl -e python3 -c "
import zipfile,sys
with zipfile.ZipFile(sys.argv[1],'a',zipfile.ZIP_DEFLATED) as z: z.write(sys.argv[2],'classes.dex')
" "/mnt$PWD/$O/base.apk" "/mnt$PWD/$O/dex/classes.dex" 2>&1 | grep -v localhost || true
$B/zipalign.exe -f 4 $O/base.apk $O/aligned.apk
$B/apksigner.bat sign --ks 'C:\Users\Syleront\.android\debug.keystore' --ks-pass pass:android --out $O/HalSwitch.apk $O/aligned.apk
$B/aapt2.exe dump badging $O/HalSwitch.apk | head -3
ls -la $O/HalSwitch.apk
