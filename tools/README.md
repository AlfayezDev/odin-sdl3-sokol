# tools

Three external tools drive generated code in this repo.

## odinbinder

Vendored under `tools/odinbinder`. It parses the Odin binding contracts in
`binding/spec/` and generates the C header, Odin foreign declarations, Kotlin
bridge, JNI glue, and Swift bridge.

```sh
odin run . -- bindings
```

Build it directly:

```sh
odin build tools/odinbinder/src -o:speed -out:build/tools/odinbinder
```

## androidgen

Vendored under `tools/androidgen` (source + Gradle wrapper). It generates the
Android Gradle project from `binding/android/android.yaml`; bindings are owned
by odinbinder.

```sh
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

`odin run . -- tools` builds odinbinder and androidgen, and verifies sokol-shdc.
