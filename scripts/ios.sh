#!/usr/bin/env bash
# iOS build: XcodeGen project around the same shared Odin/C sources.
# Requires macOS with Xcode and XcodeGen 2.44.1. SAMPLE_ID/SMOKE_FRAMES env
# vars pass through to the odin build.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'iOS project generation/build requires macOS, Xcode and XcodeGen 2.44.1.' >&2; exit 1; }
[[ $(xcodegen --version) == *2.44.1* ]] || { echo 'Install XcodeGen 2.44.1 (see README).' >&2; exit 1; }
mkdir -p build/ios build/generated
xcodegen generate --spec project.yml --project build/ios
[[ ${2:-} == --generate-only ]] && exit 0
case "${1:-iphonesimulator}" in
  iphonesimulator)
    xcodebuild -project build/ios/OdinSokol.xcodeproj -scheme odin-sokol \
      -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/ios-derived SAMPLE_ID="${SAMPLE_ID:-0}" SMOKE_FRAMES="${SMOKE_FRAMES:-0}" CODE_SIGNING_ALLOWED=NO ARCHS="$(uname -m)" build
    ;;
  iphoneos) echo 'Open build/ios/OdinSokol.xcodeproj; select your signing team and device, then Run.';;
  *) echo 'Usage: scripts/ios.sh [iphonesimulator|iphoneos]' >&2; exit 1;;
esac
