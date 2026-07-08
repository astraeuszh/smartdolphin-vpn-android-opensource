#!/usr/bin/env bash
# 增量打包：保留 build/ 与 Gradle 缓存，只重编改动的 Dart/资源。
# 首次或依赖变更仍较慢；日常改代码通常 1–4 分钟。
set -euo pipefail
export INCREMENTAL=1
export CLEAN=0
export BUILD_MODE="${BUILD_MODE:-release}"
exec "$(cd "$(dirname "$0")" && pwd)/build-apk-fast.sh" "$@"
