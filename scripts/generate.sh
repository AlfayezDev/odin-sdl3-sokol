#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  android)
    ./scripts/deps.sh
    python3 scripts/generate-android.py
    ;;
  ios)
    ./scripts/ios.sh "${2:-iphonesimulator}" --generate-only
    ;;
  *) echo 'Usage: scripts/generate.sh android | ios [iphonesimulator|iphoneos]' >&2; exit 1;;
esac
