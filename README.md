# Odin + SDL3 + sokol_gfx + native bindings

The smallest cross-platform version of this project: one triangle, one Odin
export, one platform import, Android and iOS.

## Build

```sh
odin run . -- tools      # build odinbinder + androidgen, verify sokol-shdc
odin run . -- shaders    # regenerate vendors/shaders/triangle.odin
odin run . -- bindings   # generate bridge code
odin run . -- android    # NDK build, Gradle APK, install/launch
odin run . -- ios        # xcodegen + xcodebuild (macOS only)
```

`ANDROID_BUILD_ONLY=1` packages the APK without installing it.

Generated bridge files live under ignored `generated/` folders. Every platform
build regenerates them.

## Layout

App:

- `app/main.odin` — SDL lifecycle and the triangle draw
- `app/bridge.odin` — `hello` export implementation and `bridge_init`

Bindings:

- `binding/binding.odin` — the contract: one export, one import
- `binding/README.md` — the hand-written binding flow on each platform
- `binding/android/` — Gradle spec, manifest, resources, host activity
- `binding/ios/` — SDL entry, platform handler, plist, XcodeGen spec

Build and graphics:

- `build*.odin` — Android, iOS, shader, and tool orchestration
- `sdl3_build.sh` — SDL3 source build for Android
- `shaders/triangle.glsl` — the only shader
- `vendors/sokol/` — sokol_gfx + sokol_log headers
- `vendors/sg/sg.odin` — Odin sokol_gfx bindings
- `vendors/shaders/triangle.odin` — generated shader bindings
- `tools/odinbinder/` — binding generator
- `tools/androidgen/` — Gradle project generator
- `tools/sokol-shdc/` — shader compiler

## Binding flow

```text
binding/binding.odin  ->  odinbinder  ->  generated bridge code
app/bridge.odin       ->  Odin export implementation
Android activity      ->  installs the generated PlatformHandler
iOS BridgePlatform    ->  installs the generated PlatformHandler
```

The contract, the Odin implementation, and the two platform hosts are the only
binding files written by hand. See `binding/README.md` for the exact steps.
