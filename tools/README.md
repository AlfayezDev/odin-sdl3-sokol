# tools

Two external tools drive generated code in this repo.

## androidgen

Vendored under `tools/androidgen` (source + Gradle wrapper). It generates the
Android Gradle project from `binding/android/android.yaml` and generates the
C/Kotlin/Odin/JNI bridge from `app/bridge.odin`.

```sh
odin run . -- bindings
odin run . -- android
```

Build it directly:

```sh
odin build tools/androidgen/src -o:speed -out:build/tools/androidgen
```

## sokol-shdc

Pinned prebuilt shader compiler under `tools/sokol-shdc/bin/<platform>/`.

```sh
tools/sokol-shdc/fetch.sh      # fetch the current platform binary if missing
odin run . -- shaders          # compile shaders/samples/*.glsl
```

`odin run . -- tools` builds androidgen and verifies sokol-shdc.
