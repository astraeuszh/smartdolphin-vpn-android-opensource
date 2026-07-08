#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SDRL was split out into its own top-level project (sibling of SmartDolphinVPN).
# Override with SDRL_DIR if your layout differs.
SDRL="${SDRL_DIR:-$ROOT/../../SDRL}"
ANDROID_JNI="$ROOT/android/app/src/main/jniLibs"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -f "$ROOT/android/local.properties" ]]; then
    SDK_DIR="$(grep '^sdk.dir=' "$ROOT/android/local.properties" | cut -d= -f2)"
    ANDROID_NDK_HOME="${SDK_DIR}/ndk/26.1.10909125"
  fi
fi

if [[ ! -d "${ANDROID_NDK_HOME:-}" ]]; then
  echo "Set ANDROID_NDK_HOME to your Android NDK path" >&2
  exit 1
fi

NDK="$ANDROID_NDK_HOME"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_AR="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"

cd "$SDRL"
rustup target add aarch64-linux-android armv7-linux-androideabi >/dev/null 2>&1 || true
cargo build -p sdrl-ffi --release --target aarch64-linux-android
cargo build -p sdrl-ffi --release --target armv7-linux-androideabi

mkdir -p "$ANDROID_JNI/arm64-v8a" "$ANDROID_JNI/armeabi-v7a"
cp "$SDRL/target/aarch64-linux-android/release/libsdrl_ffi.so" "$ANDROID_JNI/arm64-v8a/"
cp "$SDRL/target/armv7-linux-androideabi/release/libsdrl_ffi.so" "$ANDROID_JNI/armeabi-v7a/"

echo "Copied libsdrl_ffi.so to $ANDROID_JNI"
