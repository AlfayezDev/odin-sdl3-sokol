# Build tools

One first-party generator and two vendored tools.

## odinbinder

Lives under `tools/odinbinder`. It parses the Odin binding contract in
`binding/binding.odin` and generates the C header, Odin foreign declarations, Kotlin
bridge, JNI glue, and Swift bridge.

```sh
odin run builder -- bindings
```

Build it directly:

```sh
odin build tools/odinbinder/src -o:speed -out:build/tools/odinbinder
```

## androidgen

Vendored under `third_party/androidgen` (source + Gradle wrapper). It generates
the Android Gradle project from `binding/android/android.yaml`; bindings are
owned by odinbinder.

```sh
odin run builder -- android
```

Build it directly:

```sh
odin build third_party/androidgen/src -o:speed -out:build/tools/androidgen
```

## sokol-shdc

Pinned prebuilt shader compiler under `third_party/sokol-shdc/bin/<platform>/`.

```sh
third_party/sokol-shdc/fetch.sh      # fetch the current platform binary if missing
odin run builder -- shaders          # compile shaders/samples/*.glsl
```

`odin run builder -- tools` builds odinbinder and androidgen, and verifies sokol-shdc.
