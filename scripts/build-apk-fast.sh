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
# 持久缓存：勿用 /tmp，否则每次 Resolving dependencies 都要重新拉 pub.dev / Maven
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.local/share/smartdolphin/gradle-home}"
export PUB_CACHE="${PUB_CACHE:-$HOME/.local/share/smartdolphin/pub-cache}"
export TMPDIR="${TMPDIR:-$HOME/.local/share/smartdolphin/tmp}"
export GRADLE_OPTS="${GRADLE_OPTS:--Djava.io.tmpdir=$TMPDIR}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$GRADLE_USER_HOME" "$PUB_CACHE" "$TMPDIR"

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
# 默认直接在仓库里编（保留 .dart_tool）；仅 CI/隔离时设 BUILD_DIR=/tmp/...
if [ -n "${BUILD_DIR:-}" ]; then
  BUILD="$BUILD_DIR"
  echo "=== $(date) rsync → $BUILD ==="
  rsync -a --exclude build --exclude android/.gradle "$ROOT/" "$BUILD/"
  cd "$BUILD"
else
  BUILD="$ROOT"
  cd "$BUILD"
  echo "=== $(date) 在仓库内编译（Pub 缓存: $PUB_CACHE）==="
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
NEED_PUB=1
if [ -f .dart_tool/package_config.json ] && [ .dart_tool/package_config.json -nt pubspec.lock ] 2>/dev/null; then
  NEED_PUB=0
fi
if [ "$NEED_PUB" = 1 ]; then
  echo ">>> flutter pub get（首次或依赖变更较慢，缓存目录: $PUB_CACHE）"
  echo ">>> 心跳每秒一行；若长时间不刷 = 可能卡住"
  run_with_heartbeat "pub get" "$FLUTTER" pub get
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

MODE="${BUILD_MODE:-debug}"
echo ">>> flutter build apk ($MODE) …（通常 10–30 分钟，心跳每秒一行）"
if [ "$MODE" = "release" ]; then
  run_with_heartbeat "build apk release" "$FLUTTER" build apk --release --target-platform android-arm64
  APK="$BUILD/build/app/outputs/flutter-apk/app-release.apk"
else
  run_with_heartbeat "build apk debug" "$FLUTTER" build apk --debug --target-platform android-arm64
  APK="$BUILD/build/app/outputs/flutter-apk/app-debug.apk"
fi

ls -lh "$APK"
if adb devices 2>/dev/null | grep -q 'device$'; then
  adb install -r "$APK"
else
  echo "未检测到 USB 手机，APK 已生成：$APK"
fi
echo "=== $(date) 完成 ==="
