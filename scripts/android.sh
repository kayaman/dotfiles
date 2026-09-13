#!/usr/bin/env bash
# Sourced by install.sh; official archives from https://developer.android.com/studio.
ANDROID_STUDIO_VERSION="2026.1.4.7"
ANDROID_STUDIO_SHA256="4be240083df5ada290975d87d60fc212a3d38d4f258a1250989885a9dbc79980"
ANDROID_TOOLS_VERSION="15859902"
ANDROID_TOOLS_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
: "${ANDROID_API:=36}"
: "${ANDROID_BUILD_TOOLS:=36.0.0}"
: "${ANDROID_NDK:=27.2.12479018}"
: "${ANDROID_CMAKE:=3.22.1}"
ANDROID_STUDIO_HOME="$HOME/.local/share/android-studio"

android_present() {
  local artifact
  for artifact in platform-tools/adb platform-tools/fastboot cmdline-tools/latest/bin/sdkmanager \
    cmdline-tools/latest/bin/avdmanager emulator/emulator "build-tools/$ANDROID_BUILD_TOOLS/aapt2" \
    "ndk/$ANDROID_NDK/ndk-build" "cmake/$ANDROID_CMAKE/bin/cmake"; do
    [[ -x "$ANDROID_HOME/$artifact" ]] || return 1
  done
  [[ -x "$ANDROID_STUDIO_HOME/bin/studio.sh" && -x "$ANDROID_STUDIO_HOME/jbr/bin/java" &&
    -f "$ANDROID_HOME/platforms/android-$ANDROID_API/android.jar" &&
    -f "$ANDROID_HOME/system-images/android-$ANDROID_API/google_apis/x86_64/package.xml" ]]
}

install_android() (
  # Subshell keeps the bundled JDK and cleanup trap local to this component.
  local tmp alsa_package
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"' EXIT
  case "$DISTRO" in
    ubuntu | raspberry)
      alsa_package=libasound2
      if apt-cache show libasound2t64 > /dev/null 2>&1; then
        alsa_package=libasound2t64
      fi
      sudo apt-get install -y libgl1 libpulse0 libxkbcommon0 libnss3 "$alsa_package" android-sdk-platform-tools-common || return 1
      ;;
    fedora)
      sudo dnf install -y mesa-libGL pulseaudio-libs libxkbcommon nss alsa-lib android-tools || return 1
      ;;
    opensuse)
      sudo zypper install -y libGL1 libpulse0 libxkbcommon0 mozilla-nss libasound2 android-tools || return 1
      ;;
  esac
  if [[ ! -x "$ANDROID_STUDIO_HOME/bin/studio.sh" || ! -x "$ANDROID_STUDIO_HOME/jbr/bin/java" ]]; then
    curl -fL "https://edgedl.me.gvt1.com/android/studio/ide-zips/$ANDROID_STUDIO_VERSION/android-studio-quail4-linux.tar.gz" -o "$tmp/studio.tar.gz" || return 1
    printf '%s  %s\n' "$ANDROID_STUDIO_SHA256" "$tmp/studio.tar.gz" | sha256sum -c - || return 1
    tar -xzf "$tmp/studio.tar.gz" -C "$tmp" || return 1
    mkdir -p "$ANDROID_STUDIO_HOME" || return 1
    cp -a "$tmp/android-studio/." "$ANDROID_STUDIO_HOME/" || return 1
  fi
  export JAVA_HOME="$ANDROID_STUDIO_HOME/jbr"
  export ANDROID_HOME
  export PATH="$JAVA_HOME/bin:$PATH"
  if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
    curl -fL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_TOOLS_VERSION}_latest.zip" -o "$tmp/tools.zip" || return 1
    printf '%s  %s\n' "$ANDROID_TOOLS_SHA256" "$tmp/tools.zip" | sha256sum -c - || return 1
    unzip -q "$tmp/tools.zip" -d "$tmp/tools" || return 1
    mkdir -p "$ANDROID_HOME/cmdline-tools/latest" || return 1
    cp -a "$tmp/tools/cmdline-tools/." "$ANDROID_HOME/cmdline-tools/latest/" || return 1
  fi
  local sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  # Let sdkmanager show licenses and collect the user's answers.
  "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses || return 1
  "$sdkmanager" --sdk_root="$ANDROID_HOME" --install \
    platform-tools emulator "platforms;android-$ANDROID_API" "build-tools;$ANDROID_BUILD_TOOLS" \
    "system-images;android-$ANDROID_API;google_apis;x86_64" "ndk;$ANDROID_NDK" "cmake;$ANDROID_CMAKE" || return 1
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" || return 1
  ln -sfn "$ANDROID_STUDIO_HOME/bin/studio.sh" "$HOME/.local/bin/android-studio" || return 1
  cat > "$HOME/.local/share/applications/android-studio.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=Android Studio
Exec="$ANDROID_STUDIO_HOME/bin/studio.sh" %f
Icon=$ANDROID_STUDIO_HOME/bin/studio.svg
Terminal=false
Categories=Development;IDE;
DESKTOP
  android_present || return 1
  if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    warn "Emulator acceleration needs virtualization enabled and access to /dev/kvm (usually the kvm group; log out after changing groups)."
  fi
  info "Create a virtual device in Android Studio's Device Manager; enable USB debugging on physical devices."
  ok "Android development environment installed"
)
