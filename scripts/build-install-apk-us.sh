#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/sdvpn-android}"

unset PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL

export PATH="${FLUTTER_ROOT:-/tmp/flutter}/bin:${ANDROID_HOME:-$HOME/.local/android-sdk}/platform-tools:${ANDROID_HOME:-$HOME/.local/android-sdk}/cmdline-tools/latest/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/tmp/jdk-21}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

ensure_cmdline_tools() {
  if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    return 0
  fi
  local zip="/tmp/android-cmdline-tools.zip"
  echo "下载 Android cmdline-tools（Google 官方）..."
  curl -fSL --connect-timeout 30 --retry 3 \
    -o "$zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -q -o "$zip" -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -f "$zip"
}

ensure_sdk() {
  ensure_cmdline_tools
  yes | sdkmanager --licenses >/dev/null 2>&1 || true
  local need=()
  [ ! -d "$ANDROID_HOME/platforms/android-36" ] && need+=("platforms;android-36")
  [ ! -d "$ANDROID_HOME/build-tools/35.0.0" ] && need+=("build-tools;35.0.0")
  if [ ${#need[@]} -gt 0 ]; then
    echo "安装 SDK 组件: ${need[*]}"
    sdkmanager --install "${need[@]}"
  fi
  # NDK ~1GB，后台装，不阻塞打包（Gradle 也会按需下载）
  if [ ! -f "$ANDROID_HOME/ndk/26.1.10909125/source.properties" ]; then
    echo "NDK 后台下载中（约 1GB），日志: /tmp/ndk-install.log"
    nohup sdkmanager "ndk;26.1.10909125" >>/tmp/ndk-install.log 2>&1 &
  fi
}

if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "需要 JDK 21：请设置 JAVA_HOME（例如 /tmp/jdk-21）"
  exit 1
fi
if ! command -v flutter >/dev/null; then
  echo "缺少 flutter，请设置 FLUTTER_ROOT 或 PATH"
  exit 1
fi

ensure_sdk

echo "同步工程到 $BUILD_DIR ..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
rsync -a --exclude build --exclude .dart_tool --exclude android/.gradle \
  "$ROOT/" "$BUILD_DIR/"

cd "$BUILD_DIR"
flutter pub get
flutter build apk --release

APK="$BUILD_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo "APK: $APK ($(du -h "$APK" | cut -f1))"

adb devices
if ! adb get-state >/dev/null 2>&1; then
  echo "未检测到手机：请 USB 连接并开启调试后执行: adb install -r \"$APK\""
  exit 2
fi
adb install -r "$APK"
echo "已安装到手机"
