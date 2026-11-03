# Odin + SDL3 + sokol_gfx

One Odin app, 12 sokol_gfx demos, SDL3 as the platform layer.
All build/run logic lives in `build.odin` + `build_*.odin` — run it with odin itself.

## Build & run

Requires Odin `dev-2026-11` (pinned in `.mise.toml`).

```sh
odin run . -- tools      # build odinbinder + androidgen, verify sokol-shdc
odin run . -- shaders    # sokol-shdc -> vendors/shaders
odin run . -- bindings   # odinbinder -> C header, Odin, Kotlin, JNI, Swift

odin run . -- desktop    # macOS (Homebrew SDL3) or Linux (SDL3 built from deps/SDL3-3.2.28)
odin run . -- android    # bindings + NDK build + gradle APK + adb install/launch
odin run . -- ios        # xcodegen + xcodebuild simulator app (macOS)
```

`desktop` is the default. Env: `SAMPLE_ID` (0–11), `SMOKE_FRAMES` (exit after N frames),
`ANDROID_BUILD_ONLY=1` (package the APK without installing).

## Samples (SAMPLE_ID)

0 triangle · 1 quad · 2 mandelbrot · 3 cube · 4 instancing · 5 offscreen ·
6 dyntex · 7 mrt · 8 blend · 9 shapes · 10 sgl · 11 debugtext

## Layout

Build entry points:

- `build.odin` — CLI dispatch and shared helpers
- `build_tools.odin` — odinbinder + androidgen bootstrap
- `build_sdl.odin` — SDL config and sokol object compilation
- `build_shaders.odin` — sokol-shdc generation
- `build_desktop.odin` / `build_android.odin` / `build_ios.odin` — platform builds
- `sdl3_build.sh` — Linux/Android SDL3 source build helper

App code:

- `app/main.odin` — SDL lifecycle, frame loop, smoke check
- `app/samples.odin` — sample registry and shared helpers
- `app/sample_*.odin` — one file per demo
- `app/math4.odin` — 4x4 matrix helpers
- `app/bridge.odin` — exported Odin bridge implementations

Generated and vendored:

- `deps/SDL3-3.2.28/` — SDL3 source, downloaded on first desktop/android build (not checked in)
- `vendors/sokol/` — vendored sokol C headers
- `vendors/{sg,sgl,sdtx,sshape}/` — Odin bindings for those headers
- `vendors/shaders/` — sokol-shdc-generated Odin shader bindings
- `shaders/samples/*.glsl` — shader sources; regenerate with `odin run . -- shaders`
- `binding/README.md` — how to write a binding on each platform
- `binding/binding.odin` — the shared binding contract
- `binding/generated/`, `binding/android/generated/`, `binding/ios/generated/` — generated on demand and ignored by git
- `tools/odinbinder/` — Odin-native bridge generator
- `tools/androidgen/` — vendored Android Gradle project generator
- `tools/sokol-shdc/` — pinned shader compiler binaries + fetch script

The vendored sokol headers compile straight from the headers with impl defines,
per platform, using whatever clang the host provides (desktop), the NDK
(android), or Xcode (ios). The only other C is the generated JNI glue.
