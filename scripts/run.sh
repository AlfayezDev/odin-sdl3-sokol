#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${2:-run}" = build ]; then
  cmake -S . -B build/desktop -DCMAKE_BUILD_TYPE=Debug >/dev/null
  cmake --build build/desktop --parallel 4
else
  cmake -S . -B build/desktop -DCMAKE_BUILD_TYPE=Debug >/dev/null
  cmake --build build/desktop --parallel 4
  exec ./build/desktop/odin-sokol
fi
