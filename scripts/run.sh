#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$1" in
  desktop)
    if [ "${2:-run}" = build ]; then
      cmake -S . -B build/desktop -DCMAKE_BUILD_TYPE=Debug >/dev/null
      cmake --build build/desktop --parallel 4
    else
      cmake -S . -B build/desktop -DCMAKE_BUILD_TYPE=Debug >/dev/null
      cmake --build build/desktop --parallel 4
      exec ./build/desktop/odin-sokol
    fi
    ;;
  android)
    adb=${ADB:-adb}
    build_only=false
    [ "${2:-run}" = build ] && build_only=true
    ./scripts/deps.sh >/dev/null
    bash scripts/generate.sh android >/dev/null
    (cd android && ./gradlew --no-daemon :app:assembleDebug)
    if [ "$build_only" = true ]; then exit 0; fi
    "$adb" install -r android/app/build/outputs/apk/debug/app-debug.apk
    "$adb" shell am force-stop dev.alfayez.odinsokol 2>/dev/null || true
    "$adb" shell am start -n dev.alfayez.odinsokol/.OdinsokolActivity
    ;;
  ios)
    echo 'iOS: open ios/ in Xcode (planned)' >&2
    exit 2
    ;;
  *)
    echo "Usage: run.sh [desktop|android|ios] [run|build]" >&2
    exit 2
    ;;
esac
