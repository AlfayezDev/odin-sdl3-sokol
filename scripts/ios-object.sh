#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
case "$PLATFORM_NAME" in
  iphoneos) platform=iphone;;
  iphonesimulator) platform=iphonesimulator;;
  *) echo "Unsupported platform: $PLATFORM_NAME" >&2; exit 1;;
esac
objects=()
for arch in $ARCHS; do
  object="$DERIVED_FILE_DIR/odin-$arch.o"
  "$root/scripts/odin-object.sh" "$platform" "$arch" "$object"
  objects+=("$object")
done
xcrun lipo -create "${objects[@]}" -output "$DERIVED_FILE_DIR/odin-app.o"
