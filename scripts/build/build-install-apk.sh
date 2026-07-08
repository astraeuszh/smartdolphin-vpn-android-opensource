#!/usr/bin/env bash
# 本地打包并安装到已连接手机（需 USB 调试 + adb）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 国内镜像（Flutter / Pub）
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

export PATH="${FLUTTER_ROOT:-/tmp/flutter}/bin:${ANDROID_HOME:-$HOME/.local/android-sdk}/platform-tools:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/tmp/jdk-21}"

ensure_jdk21() {
  if [ -x "$JAVA_HOME/bin/java" ]; then
    return 0
  fi
  local tgz="/tmp/jdk21-cn.tgz"
  local urls=(
    "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/linux/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz"
  )
  echo "下载 JDK 21（国内镜像）..."
  for u in "${urls[@]}"; do
    if curl -fSL --connect-timeout 20 --retry 2 -o "$tgz" "$u"; then
      break
    fi
    rm -f "$tgz"
  done
  [ -f "$tgz" ] || { echo "JDK 下载失败"; exit 1; }
  rm -rf "$JAVA_HOME"
  mkdir -p "$JAVA_HOME"
  tar -xzf "$tgz" -C "$JAVA_HOME" --strip-components=1
  rm -f "$tgz"
}

ensure_jdk21
if ! command -v flutter >/dev/null; then
  echo "缺少 flutter，请设置 FLUTTER_ROOT 或把 /tmp/flutter/bin 加入 PATH"
  exit 1
fi

cd "$ROOT"
flutter pub get
flutter build apk --release
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
adb devices
adb install -r "$APK"
echo "已安装: $APK"
