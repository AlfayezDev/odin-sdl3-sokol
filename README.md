# Odin + SDL3 + sokol_gfx

One Odin app, 12 sokol_gfx demos, SDL3 as the platform layer.
All build/run logic lives in `builder/` — run it with odin itself.

## Build & run

Requires Odin `dev-2026-11` (pinned in `.mise.toml`).

```sh
odin run builder -- tools      # build odinbinder + androidgen, verify sokol-shdc
odin run builder -- shaders    # sokol-shdc -> vendors/shaders
odin run builder -- bindings   # odinbinder -> C header, Odin, Kotlin, JNI, Swift

odin run builder -- desktop    # macOS (Homebrew SDL3) or Linux (SDL3 built from deps/SDL3-3.2.28)
odin run builder -- android    # prebuilt SDL3 AAR + NDK build + gradle APK + adb install/launch
odin run builder -- ios        # xcodegen + xcodebuild simulator app (macOS)
```

`desktop` is the default. Env: `SAMPLE_ID` (0–11), `SMOKE_FRAMES` (exit after N frames),
`ANDROID_BUILD_ONLY=1` (package the APK without installing).

## Samples (SAMPLE_ID)

0 triangle · 1 quad · 2 mandelbrot · 3 cube · 4 instancing · 5 offscreen ·
6 dyntex · 7 mrt · 8 blend · 9 shapes · 10 sgl · 11 debugtext

## Layout

Build entry points:

- `builder/build.odin` — CLI dispatch and shared helpers
- `builder/build_tools.odin` — odinbinder + androidgen bootstrap
- `builder/build_sdl.odin` — SDL config and sokol object compilation
- `builder/build_shaders.odin` — sokol-shdc generation
- `builder/build_desktop.odin` / `builder/build_android.odin` / `builder/build_ios.odin` — platform builds
- `builder/sdl3_build.sh` — Linux SDL3 source build helper for desktop

App code:

- `app/main.odin` — SDL lifecycle, frame loop, smoke check
- `app/samples.odin` — sample registry and shared helpers
- `app/sample_*.odin` — one file per demo
- `app/math4.odin` — 4x4 matrix helpers
- `app/bridge.odin` — exported Odin bridge implementations

Generated and vendored:

- `deps/SDL3-3.2.28/` — SDL3 source for desktop/iOS, downloaded on first build (not checked in)
- `deps/SDL3-3.2.28.aar` — prebuilt SDL3 Android package, downloaded on first Android build (not checked in)
- `vendors/sokol/` — vendored sokol C headers
- `vendors/{sg,sgl,sdtx,sshape}/` — Odin bindings for those headers
- `vendors/shaders/` — sokol-shdc-generated Odin shader bindings
- `shaders/samples/*.glsl` — shader sources; regenerate with `odin run builder -- shaders`
- `binding/README.md` — how to write a binding on each platform
- `app/bridge.odin` — the binding contract and Odin implementation
- `generated/` — generated on demand and ignored by git
- `tools/odinbinder/` — Odin-native bridge generator
- `third_party/androidgen/` — vendored Android Gradle project generator
- `third_party/sokol-shdc/` — pinned shader compiler binaries + fetch script

The vendored sokol headers compile straight from the headers with impl defines,
per platform, using whatever clang the host provides (desktop), the NDK
(android), or Xcode (ios). The only other C is the generated JNI glue.
