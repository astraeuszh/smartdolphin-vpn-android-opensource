#!/usr/bin/env bash
set -euo pipefail
# 国内网络默认走 Flutter 中文社区镜像；外网直连时可在命令前覆盖为空或官方源。
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/.local/flutter}"
JAVA_HOME="${JAVA_HOME:-$HOME/.local/jdk-21}"

ensure_jdk21() {
  if [ -x "$JAVA_HOME/bin/java" ]; then
    return 0
  fi
  local tgz="/tmp/jdk21-cn.tgz"
  local url="https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/linux/OpenJDK21U-jdk_x64_linux_hotspot_21.0.11_10.tar.gz"
  echo ">>> 下载 JDK 21（国内镜像）→ $JAVA_HOME"
  curl -fSL --connect-timeout 30 --retry 3 -o "$tgz" "$url"
  rm -rf "$JAVA_HOME"
  mkdir -p "$JAVA_HOME"
  tar -xzf "$tgz" -C "$JAVA_HOME" --strip-components=1
  rm -f "$tgz"
}

if [ ! -x "$JAVA_HOME/bin/java" ]; then
  for j in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk "$HOME/.local/jdk-21"; do
    [ -x "$j/bin/java" ] && JAVA_HOME="$j" && break
  done
fi
if [ ! -x "$JAVA_HOME/bin/java" ]; then
  ensure_jdk21
fi
[ -x "$JAVA_HOME/bin/java" ] || { echo "需要 JDK（21 优先）：安装 java-21-openjdk-devel 或解压到 ~/.local/jdk-21"; exit 1; }
ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/android-sdk}"
FLUTTER="$FLUTTER_ROOT/bin/flutter"
export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:/usr/bin:/bin:$PATH"
export JAVA_HOME
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
# Gradle/临时文件放 btrfs 家目录，避免 exfat 分区上数万小文件 I/O 拖死编译
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.cache/smartdolphin/gradle-home}"
export TMPDIR="${TMPDIR:-$HOME/.cache/smartdolphin/build-tmp}"
export GRADLE_OPTS="${GRADLE_OPTS:--Djava.io.tmpdir=$TMPDIR}"
export PUB_CACHE="${PUB_CACHE:-$HOME/.local/share/smartdolphin/pub-cache}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$GRADLE_USER_HOME" "$PUB_CACHE" "$TMPDIR"

INCREMENTAL="${INCREMENTAL:-1}"
CLEAN="${CLEAN:-0}"

[ -x "$FLUTTER" ] || { echo "缺少 $FLUTTER"; exit 1; }
[ -f "$ANDROID_HOME/ndk/26.1.10909125/source.properties" ] || {
  echo "缺少 NDK: $ANDROID_HOME/ndk/26.1.10909125"; exit 1
}

# 每秒打印心跳，长时间无新行 = 进程可能卡死/已退出
HEARTBEAT_PID=""
stop_heartbeat() {
  if [ -n "${HEARTBEAT_PID:-}" ] && kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi
  HEARTBEAT_PID=""
}
start_heartbeat() {
  local label="${1:-running}"
  local watch_pid="${2:-$$}"
  stop_heartbeat
  (
    local start tick now elapsed
    start=$(date +%s)
    tick=0
    while kill -0 "$watch_pid" 2>/dev/null; do
      tick=$((tick + 1))
      now=$(date +%H:%M:%S)
      elapsed=$(( $(date +%s) - start ))
      printf '[%s] ♥ #%04d %s 已跑 %ds (watch pid %s)\n' "$now" "$tick" "$label" "$elapsed" "$watch_pid"
      sleep 1
    done
  ) &
  HEARTBEAT_PID=$!
}
run_with_heartbeat() {
  local label="$1"
  shift
  (
    "$@"
  ) &
  local cmd_pid=$!
  start_heartbeat "$label" "$cmd_pid"
  wait "$cmd_pid"
  local status=$?
  stop_heartbeat
  return "$status"
}
trap stop_heartbeat EXIT

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 默认在本机 btrfs 缓存目录编译，避开 /run/media 上的 exfat/fuseblk 小文件 I/O 问题。
# BUILD_DIR 内的 build/ 会保留，因此仍是增量打包；源码从仓库 rsync 同步过去。
BUILD="${BUILD_DIR:-$HOME/.cache/smartdolphin/android-build/SmartDolphinVPNAndroid}"
mkdir -p "$BUILD"
if [ "$BUILD" != "$ROOT" ]; then
  echo "=== $(date) 本地增量构建：$ROOT → $BUILD ==="
  rsync -a --delete \
    --exclude build \
    --exclude android/.gradle \
    --exclude .dart_tool/flutter_build \
    "$ROOT/" "$BUILD/"
  cd "$BUILD"
else
  cd "$BUILD"
  echo "=== $(date) 在仓库内编译（增量: $INCREMENTAL，Gradle: $GRADLE_USER_HOME）==="
fi

if [ "$CLEAN" = "1" ]; then
  echo ">>> CLEAN=1：清理 build/（全量重编，通常 10–20 分钟）"
  rm -rf "$BUILD/build" "$BUILD/android/.gradle" "$BUILD/android/app/build"
else
  echo ">>> 保留 build/ 缓存（增量编译，改 Dart 代码通常 1–4 分钟）"
fi

# Flutter includeBuild 默认仅 google()；网络差时可设 USE_CN_MAVEN=1 强制全镜像
FLUTTER_GRADLE_SETTINGS="$FLUTTER_ROOT/packages/flutter_tools/gradle/settings.gradle.kts"
if [ "${USE_CN_MAVEN:-0}" = "1" ] && [ -f "$FLUTTER_GRADLE_SETTINGS" ]; then
  echo ">>> USE_CN_MAVEN=1：Flutter Gradle 仓库 → 阿里云"
  cat > "$FLUTTER_GRADLE_SETTINGS" <<'FLUTTER_GRADLE_EOF'
pluginManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
    }
}
FLUTTER_GRADLE_EOF
fi

# 仅当 pub 锁文件变化时才 pub get，避免每次 Resolving dependencies 卡很久
# exfat 上 -nt 只有秒级精度，用 pubspec.yaml/lock/config 三者关系判断
NEED_PUB=1
if [ -f .dart_tool/package_config.json ] && [ -f pubspec.lock ]; then
  if [ ! pubspec.yaml -nt pubspec.lock ] 2>/dev/null && \
     [ ! pubspec.lock -nt .dart_tool/package_config.json ] 2>/dev/null; then
    NEED_PUB=0
  fi
fi
USE_NO_PUB=0
if [ "$INCREMENTAL" = "1" ] && [ "$NEED_PUB" = 0 ]; then
  USE_NO_PUB=1
fi
if [ "$NEED_PUB" = 1 ]; then
  echo ">>> dart pub get --offline（避免在线 Resolving dependencies 卡死）"
  if ! run_with_heartbeat "pub get offline" "$FLUTTER" pub get --offline; then
    echo ">>> 离线缓存不完整，改在线 pub get（可能较慢）"
    run_with_heartbeat "pub get online" "$FLUTTER" pub get
  fi
else
  echo ">>> 跳过 pub get（依赖未变，用已有 .dart_tool）"
fi

PROP=android/gradle.properties
# 强制 Gradle 用 JDK 21（避免系统 Java 25 不兼容）
if grep -q '^org.gradle.java.home=' "$PROP" 2>/dev/null; then
  sed -i "s|^org.gradle.java.home=.*|org.gradle.java.home=$JAVA_HOME|" "$PROP"
else
  echo "org.gradle.java.home=$JAVA_HOME" >> "$PROP"
fi
# Gradle 发行包走腾讯云镜像（避免 services.gradle.org SSL 失败）
WRAPPER=android/gradle/wrapper/gradle-wrapper.properties
if grep -q 'services.gradle.org' "$WRAPPER" 2>/dev/null; then
  sed -i 's|services.gradle.org/distributions|mirrors.cloud.tencent.com/gradle|g' "$WRAPPER"
fi
if ! grep -q '^org.gradle.jvmargs=' "$PROP" 2>/dev/null; then
  cat >> "$PROP" <<'EOF'
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
org.gradle.parallel=true
org.gradle.workers.max=4
org.gradle.daemon=true
EOF
fi
if ! grep -q '^org.gradle.caching=' "$PROP" 2>/dev/null; then
  echo "org.gradle.caching=true" >> "$PROP"
fi
if ! grep -q '^org.gradle.daemon=' "$PROP" 2>/dev/null; then
  echo "org.gradle.daemon=true" >> "$PROP"
fi

MODE="${BUILD_MODE:-debug}"
PUB_FLAG=()
if [ "$USE_NO_PUB" = 1 ]; then
  PUB_FLAG=(--no-pub)
  echo ">>> flutter build apk ($MODE) 增量模式（--no-pub，跳过 pub + 复用缓存）…"
else
  echo ">>> flutter build apk ($MODE) …（依赖变更或首次，可能 5–15 分钟）"
fi
if [ "$MODE" = "release" ]; then
  run_with_heartbeat "build apk release" "$FLUTTER" build apk --release --target-platform android-arm64 "${PUB_FLAG[@]}"
  APK="$BUILD/build/app/outputs/flutter-apk/app-release.apk"
else
  run_with_heartbeat "build apk debug" "$FLUTTER" build apk --debug --target-platform android-arm64 "${PUB_FLAG[@]}"
  APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
fi

/bin/ls -lh "$APK"
if adb devices 2>/dev/null | grep -q 'device$'; then
  adb install -r "$APK"
else
  echo "未检测到 USB 手机，APK 已生成：$APK"
fi
echo "=== $(date) 完成 ==="
