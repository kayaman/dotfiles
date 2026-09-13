#!/usr/bin/env bash
# Hermetic checks: partial installs must fail doctor; failed downloads must stop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/android.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ANDROID_HOME="$tmp/sdk"
ANDROID_STUDIO_HOME="$tmp/studio"
if android_present; then
  echo 'FAIL: missing environment reported present'
  exit 1
fi
for artifact in platform-tools/adb platform-tools/fastboot cmdline-tools/latest/bin/sdkmanager \
  cmdline-tools/latest/bin/avdmanager emulator/emulator "build-tools/$ANDROID_BUILD_TOOLS/aapt2" \
  "ndk/$ANDROID_NDK/ndk-build" "cmake/$ANDROID_CMAKE/bin/cmake"; do
  mkdir -p "$(dirname "$ANDROID_HOME/$artifact")"
  touch "$ANDROID_HOME/$artifact"
  chmod +x "$ANDROID_HOME/$artifact"
done
mkdir -p "$ANDROID_STUDIO_HOME/bin" "$ANDROID_STUDIO_HOME/jbr/bin" \
  "$ANDROID_HOME/platforms/android-$ANDROID_API" \
  "$ANDROID_HOME/system-images/android-$ANDROID_API/google_apis/x86_64"
touch "$ANDROID_STUDIO_HOME/bin/studio.sh" "$ANDROID_STUDIO_HOME/jbr/bin/java" \
  "$ANDROID_HOME/platforms/android-$ANDROID_API/android.jar" \
  "$ANDROID_HOME/system-images/android-$ANDROID_API/google_apis/x86_64/package.xml"
chmod +x "$ANDROID_STUDIO_HOME/bin/studio.sh" "$ANDROID_STUDIO_HOME/jbr/bin/java"
android_present
rm "$ANDROID_HOME/platform-tools/adb"
if android_present; then
  echo 'FAIL: partial environment reported present'
  exit 1
fi
ANDROID_STUDIO_HOME="$tmp/missing-studio"
DISTRO=fedora
sudo() { return 0; }
curl() { return 1; }
if install_android; then
  echo 'FAIL: download failure ignored'
  exit 1
fi
[[ ! -e "$ANDROID_STUDIO_HOME" ]]
echo 'PASS: Android presence, partial installation and download failure checks'
