#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
odin=${ODIN:-$(command -v odin || echo /opt/homebrew/bin/odin)}
platform=$1
arch=$2
out=$3
args=()
case "$platform/$arch" in
  android/arm64-v8a) args=(-target:linux_arm64 -subtarget:android -minimum-os-version:29 -build-mode:obj -no-entry-point);;
  android/x86_64) args=(-target:linux_amd64 -subtarget:android -minimum-os-version:29 -build-mode:obj -no-entry-point);;
  iphone/arm64) args=(-target:darwin_arm64 -subtarget:iphone -minimum-os-version:17.4 -build-mode:obj -no-entry-point);;
  iphonesimulator/arm64) args=(-target:darwin_arm64 -subtarget:iphonesimulator -minimum-os-version:17.4 -build-mode:obj -no-entry-point);;
  iphonesimulator/x86_64) args=(-target:darwin_amd64 -subtarget:iphonesimulator -minimum-os-version:17.4 -build-mode:obj -no-entry-point);;
  desktop/*)
    # odin builds the executable itself; SDL3-static must exist already
    args=(-build-mode:exe)
    out="${out%.o}"
    ;;
  *) echo "Unsupported platform/architecture: $platform/$arch" >&2; exit 1;;
esac

# vendored sokol headers: the only C in the build, compiled straight from
# the headers (impl defines, no project C sources)
sokol_objs=()
if [[ "$platform" == desktop ]]; then
  build_dir=$(dirname "$out")
  for unit in gfx gl debugtext shape; do
    case "$unit" in
      gfx)       header=sokol_gfx.h;       flags="-DSOKOL_IMPL -include sokol_log.h";;
      gl)        header=sokol_gl.h;        flags="-DSOKOL_GL_IMPL -include sokol_gfx.h";;
      debugtext) header=sokol_debugtext.h; flags="-DSOKOL_DEBUGTEXT_IMPL -include sokol_gfx.h";;
      shape)     header=sokol_shape.h;     flags="-DSOKOL_SHAPE_IMPL -include sokol_gfx.h";;
    esac
    obj="$build_dir/sokol_$unit.o"
    clang -x c -c -O2 -DSOKOL_NO_ENTRY -DSOKOL_GLCORE $flags \
      -I"$root/vendors/sokol" "$root/vendors/sokol/$header" -o "$obj"
    sokol_objs+=("$obj")
  done
  linker="-L$build_dir/deps/SDL3-3.2.28 -lSDL3 ${sokol_objs[*]} -lX11 -lGL -ldl -lpthread -lm"
  args+=(-extra-linker-flags:"$linker")
fi

"$odin" build "$root/app" -collection:libs="$root/vendors" \
  -define:SMOKE_FRAMES="${SMOKE_FRAMES:-0}" -define:SAMPLE_ID="${SAMPLE_ID:-0}" \
  -o:speed ${args[@]+"${args[@]}"} -out:"$out"

# android/ios: rename our entry to the SDL_main symbol SDL expects
if [[ "$platform" == android ]]; then
  objcopy_bin="$ODIN_ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy"
  [[ -x "$objcopy_bin" ]] || objcopy_bin=$(ls "$ODIN_ANDROID_NDK"/toolchains/llvm/prebuilt/*/bin/llvm-objcopy 2>/dev/null | head -1)
  "$objcopy_bin" --redefine-sym sdl_main_provider=SDL_main "$out"
fi
