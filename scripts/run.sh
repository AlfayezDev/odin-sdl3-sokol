#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$1" in
  desktop)
    bash scripts/build-sdl3.sh desktop >/dev/null
    SAMPLE_ID=${SAMPLE_ID:-0} SMOKE_FRAMES=${SMOKE_FRAMES:-0} bash scripts/odin-object.sh desktop native build/desktop/odin-sokol
    if [ "${2:-run}" = run ]; then
      exec ./build/desktop/odin-sokol
    fi
    ;;
  android)
    adb=${ADB:-adb}
    build_only=false
    [ "${2:-run}" = build ] && build_only=true
    ./scripts/deps.sh >/dev/null
    bash scripts/generate.sh android >/dev/null
    if [[ -z "${ANDROID_NDK:-}" ]]; then
      ANDROID_NDK=$(ls -d "$HOME/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    fi
    abi=arm64-v8a
    out_dir=build/android/$abi
    mkdir -p "$out_dir" android/app/src/main/jniLibs/$abi
    # SDL3 shared + odin object + sokol header objects (build-sdl3 exports ANDROID_NDK)
    bash scripts/build-sdl3.sh android $abi >/dev/null
    SAMPLE_ID=${SAMPLE_ID:-0} SMOKE_FRAMES=${SMOKE_FRAMES:-0} ANDROID_NDK="$ANDROID_NDK" ODIN_ANDROID_NDK="$ANDROID_NDK" \
      bash scripts/odin-object.sh android $abi "$out_dir/odin-app.o"
    cc="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
    for unit in gfx gl debugtext shape; do
      case "$unit" in
        gfx)       header=sokol_gfx.h;       flags="-DSOKOL_IMPL -include sokol_log.h";;
        gl)        header=sokol_gl.h;        flags="-DSOKOL_GL_IMPL -include sokol_gfx.h";;
        debugtext) header=sokol_debugtext.h; flags="-DSOKOL_DEBUGTEXT_IMPL -include sokol_gfx.h";;
        shape)     header=sokol_shape.h;     flags="-DSOKOL_SHAPE_IMPL -include sokol_gfx.h";;
      esac
      $cc -x c -c -O2 -DSOKOL_NO_ENTRY -DSOKOL_GLES3 $flags -I vendors/sokol \
        vendors/sokol/$header -o "$out_dir/sokol_$unit.o"
    done
    $cc -shared -o "$out_dir/libmain.so" "$out_dir/odin-app.o" "$out_dir"/sokol_*.o \
      -L"$out_dir" -lSDL3 -lEGL -lGLESv3 -llog -landroid -ldl -lm
    cp "$out_dir/libSDL3.so" "$out_dir/libmain.so" android/app/src/main/jniLibs/$abi/
    (cd android && ./gradlew --no-daemon :app:assembleDebug)
    if [ "$build_only" = true ]; then exit 0; fi
    "$adb" install -r android/app/build/outputs/apk/debug/app-debug.apk
    "$adb" shell am force-stop dev.alfayez.odinsokol 2>/dev/null || true
    "$adb" shell am start -n dev.alfayez.odinsokol/.OdinsokolActivity
    ;;
  ios)
    ./scripts/ios.sh "${2:-iphonesimulator}"
    ;;
  *)
    echo "Usage: run.sh [desktop|android|ios] [run|build]" >&2
    exit 2
    ;;
esac
