# odinbinder

Odin-native binding generator. Parses binding contracts written as Odin
declarations and emits the C ABI header, Odin foreign declarations, Kotlin
bridge + JNI glue, and Swift bridge.

No YAML schema, no separate IDL: the contract is Odin, parsed with
`core:odin/parser`.

## Contract layout

```text
binding/spec/binding.odin           # shared declarations + _config metadata
binding/spec/binding.android.odin   # Android overrides/additions
binding/spec/binding.ios.odin       # iOS overrides/additions
```

Target files merge over the shared file by declaration name.

```odin
@(odinbinder={
    name = "bridge",
    android_package = "dev.example.app",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}

@(odinbinder={direction="export"})          // Odin implements, platform calls
hello :: proc "c" () -> cstring

@(odinbinder={direction="import", thread="ui"})  // platform implements, Odin calls
show_toast :: proc "c" (msg: cstring)
```

A body infers `export`; no body infers `import`. The explicit `direction`
attribute wins.

## Usage

```sh
odin build tools/odinbinder/src -o:speed -out:build/tools/odinbinder

build/tools/odinbinder generate --target all --spec binding/spec \
  --header binding/api/bridge.h \
  --odin vendors/bridge/bridge.odin \
  --kotlin binding/android/java/dev/example/app/OdinBridge.kt \
  --jni build/gen/bridge_jni.c \
  --swift binding/ios/GameBridge.swift

build/tools/odinbinder check --spec binding/spec
```

`--target android|ios|desktop|all`. With `--target all`, the header and Odin
declarations are the union of every target view, while each platform's
Kotlin/Swift output comes from its own merged view.

## Types

`i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool cstring`

Records, enums, arrays, objects, callbacks, async, and `b32` are not supported
yet.

## Rules

- Declarations use `proc "c"`.
- Imports cannot return `cstring`.
- Binding spec files are contracts, not compiled app code. If a tool compiles
  one, pass `-custom-attribute:odinbinder`; do not compile all target files as
  one package because overrides redeclare names.
