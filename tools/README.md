# Build tools

## odinbinder

Lives under `tools/odinbinder`. It parses the binding contract in
`app/bridge.odin` and generates the Kotlin bridge, JNI glue, and Swift bridge.

```sh
odin run builder -- bindings
odin run builder -- test
```

Build it directly:

```sh
odin build tools/odinbinder/src -o:speed -out:build/tools/odinbinder
```

## sokol-shdc

Pinned prebuilt shader compiler under `third_party/sokol-shdc/bin/<platform>/`.

```sh
third_party/sokol-shdc/fetch.sh      # fetch the current platform binary if missing
odin run builder -- shaders          # compile shaders/samples/*.glsl
```

`odin run builder -- tools` builds odinbinder and verifies sokol-shdc.
