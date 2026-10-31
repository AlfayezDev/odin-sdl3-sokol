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

# vendored sokol headers: the only C in the build, compiled per arch
sokol_objects=()
for unit in gfx gl debugtext shape; do
  case "$unit" in
    gfx)       header=sokol_gfx.h;      flags="-DSOKOL_IMPL -include sokol_log.h";;
    gl)        header=sokol_gl.h;       flags="-DSOKOL_GL_IMPL -include sokol_gfx.h";;
    debugtext) header=sokol_debugtext.h; flags="-DSOKOL_DEBUGTEXT_IMPL -include sokol_gfx.h";;
    shape)     header=sokol_shape.h;    flags="-DSOKOL_SHAPE_IMPL -include sokol_gfx.h";;
  esac
  arch_objects=()
  for arch in $ARCHS; do
    obj="$DERIVED_FILE_DIR/sokol_$unit-$arch.o"
    xcrun -sdk "$SDKROOT" clang -x c -c -arch "$arch" -O2 -DSOKOL_NO_ENTRY -DSOKOL_GLES3 $flags -I"$root/vendors/sokol" "$root/vendors/sokol/$header" -o "$obj"
    arch_objects+=("$obj")
  done
  objcopy --redefine-sym sdl_main_provider=SDL_main "$DERIVED_FILE_DIR/odin-app.o"
  if [ ${#arch_objects[@]} -gt 1 ]; then
    xcrun lipo -create "${arch_objects[@]}" -output "$DERIVED_FILE_DIR/sokol_$unit.o"
  else
    cp "${arch_objects[0]}" "$DERIVED_FILE_DIR/sokol_$unit.o"
  fi
  sokol_objects+=("$DERIVED_FILE_DIR/sokol_$unit.o")
done
