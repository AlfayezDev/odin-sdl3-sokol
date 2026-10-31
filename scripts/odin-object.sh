#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# Xcode GUI script phases have a restricted PATH without /opt/homebrew/bin.
odin=${ODIN:-$(command -v odin || echo /opt/homebrew/bin/odin)}
platform=$1
arch=$2
out=$3
args=()
case "$platform/$arch" in
  android/arm64-v8a) args=(-target:linux_arm64 -subtarget:android -minimum-os-version:29);;
  android/x86_64) args=(-target:linux_amd64 -subtarget:android -minimum-os-version:29);;
  iphone/arm64) args=(-target:darwin_arm64 -subtarget:iphone -minimum-os-version:17.4);;
  iphonesimulator/arm64) args=(-target:darwin_arm64 -subtarget:iphonesimulator -minimum-os-version:17.4);;
  iphonesimulator/x86_64) args=(-target:darwin_amd64 -subtarget:iphonesimulator -minimum-os-version:17.4);;
  desktop/*) ;;
  *) echo "Unsupported platform/architecture: $platform/$arch" >&2; exit 1;;
esac
"$odin" build "$root/app" -collection:libs="$root/vendors" -define:SMOKE_FRAMES="${SMOKE_FRAMES:-0}" -no-entry-point -build-mode:obj -use-single-module -o:speed -reloc-mode:pic ${args[@]+"${args[@]}"} -out:"$out"
