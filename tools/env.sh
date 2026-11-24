# Toolchain setup shared by the build scripts (sourced, not run). Works in Git Bash on Windows
# and on Linux. Every variable can be overridden from the environment:
#   ANDROID_HOME   Android SDK (default: $ANDROID_SDK_ROOT, ~/Android/Sdk, ~/AppData/Local/Android/Sdk)
#   NDK            NDK root (default: $ANDROID_NDK_HOME, else the newest $ANDROID_HOME/ndk/*)
#   BUILD_TOOLS    build-tools version (default: 36.0.0 if installed, else the newest)
#   PLATFORM       platforms/<PLATFORM>/android.jar (default: android-36)
#   JAVA_HOME      JDK used by javac/d8/apksigner (JDK 17 recommended; default: ~/.jdks/temurin-17*)
#   KEYSTORE, KS_PASS, KS_ALIAS   key for the zoomfix APK (default: the Android debug key)
#   PYTHON         python3 command (default: python3 if it works, else `wsl -e python3` on Windows)
#   PATCHELF       patchelf command (default: patchelf if found, else `wsl -e patchelf` on Windows)

die() { echo "error: $*" >&2; exit 1; }
upath() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi; }
wpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

R=$(cd "$(dirname "$0")/.." && pwd)

# --- Android SDK / NDK
[ -n "${ANDROID_HOME:-}" ] || ANDROID_HOME=${ANDROID_SDK_ROOT:-}
if [ -z "$ANDROID_HOME" ]; then
    for d in "$HOME/Android/Sdk" "$HOME/AppData/Local/Android/Sdk"; do [ -d "$d" ] && ANDROID_HOME=$d && break; done
fi
[ -n "$ANDROID_HOME" ] || die "Android SDK not found, set ANDROID_HOME"
ANDROID_HOME=$(upath "$ANDROID_HOME")
if [ -z "${BUILD_TOOLS:-}" ]; then
    if [ -d "$ANDROID_HOME/build-tools/36.0.0" ]; then BUILD_TOOLS=36.0.0
    else BUILD_TOOLS=$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1); fi
fi
BT=$ANDROID_HOME/build-tools/$BUILD_TOOLS
ANDROID_JAR=$ANDROID_HOME/platforms/${PLATFORM:-android-36}/android.jar
[ -f "$ANDROID_JAR" ] || die "missing $ANDROID_JAR (install platform ${PLATFORM:-android-36})"
[ -n "${NDK:-}" ] || NDK=${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)}
[ -n "$NDK" ] || die "NDK not found, set NDK"
NDK=$(upath "$NDK")
NDKBIN=$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin | head -1)

# .exe/.bat suffixes on Windows
X=; BAT=
[ -f "$BT/aapt2.exe" ] && X=.exe && BAT=.bat
AAPT2=$BT/aapt2$X; ZIPALIGN=$BT/zipalign$X; D8=$BT/d8$BAT; APKSIGNER=$BT/apksigner$BAT
CLANG=$NDKBIN/clang$X; CLANGXX=$NDKBIN/clang++$X; READELF=$NDKBIN/llvm-readelf$X
for t in "$AAPT2" "$ZIPALIGN" "$D8" "$APKSIGNER" "$CLANG"; do [ -f "$t" ] || die "missing $t"; done

# --- JDK
if [ -z "${JAVA_HOME:-}" ]; then
    JAVA_HOME=$(ls -d "$HOME"/.jdks/temurin-17* 2>/dev/null | tail -1)
    [ -n "$JAVA_HOME" ] || JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
fi
JAVA_HOME_U=$(upath "$JAVA_HOME"); JAVAC=$JAVA_HOME_U/bin/javac$X
[ -f "$JAVAC" ] || die "javac not found in JAVA_HOME=$JAVA_HOME"
export JAVA_HOME; [ -n "$X" ] && JAVA_HOME=$(wpath "$JAVA_HOME_U")

# --- signing key for our own small APKs
KEYSTORE=${KEYSTORE:-$HOME/.android/debug.keystore}; KS_PASS=${KS_PASS:-android}; KS_ALIAS=${KS_ALIAS:-}
apksign() { # in out
    [ -f "$KEYSTORE" ] || die "keystore $KEYSTORE not found (set KEYSTORE/KS_PASS/KS_ALIAS)"
    "$APKSIGNER" sign --ks "$(wpath "$KEYSTORE")" --ks-pass "pass:$KS_PASS" ${KS_ALIAS:+--ks-key-alias "$KS_ALIAS"} --out "$2" "$1"
}

# --- python3 / patchelf: native, or through WSL on Windows (paths are translated to /mnt/<drive>)
if [ -n "${PYTHON:-}" ]; then :
elif python3 -c 'import sys' >/dev/null 2>&1; then PYTHON=python3
elif command -v wsl >/dev/null 2>&1; then PYTHON="wsl -e python3"
else die "python3 not found"; fi
if [ -n "${PATCHELF:-}" ]; then :
elif command -v patchelf >/dev/null 2>&1; then PATCHELF=patchelf
elif command -v wsl >/dev/null 2>&1; then PATCHELF="wsl -e patchelf"
else die "patchelf not found"; fi
hp() { # host path for PYTHON/PATCHELF: /c/x -> /mnt/c/x under WSL
    case "$PYTHON $PATCHELF" in *wsl*) case "$1" in /[a-zA-Z]/*) echo "/mnt$1"; return;; esac;; esac; echo "$1"; }
# (WSL prints a UTF-16 "localhost proxy" warning on stderr; drop it)
quiet_wsl() { local rc; "$@" </dev/null 2>&1 | tr -d '\000' | { grep -v 'localhost proxy' || true; }; rc=${PIPESTATUS[0]}; return $rc; }
py() { MSYS_NO_PATHCONV=1 quiet_wsl $PYTHON "$@"; }
pelf() { MSYS_NO_PATHCONV=1 quiet_wsl $PATCHELF "$@"; }

check_md5() { [ "$(md5sum "$1" | cut -d' ' -f1)" = "$2" ] || die "md5 mismatch: $1 (expected $2)"; }
