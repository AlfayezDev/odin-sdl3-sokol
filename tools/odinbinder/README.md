# odinbinder

Odin-native binding generator. Parses binding contracts written as Odin
declarations and emits the C ABI header, Kotlin bridge + JNI glue, and Swift
bridge.

No YAML schema, no separate IDL: the contract is Odin, parsed with
`core:odin/parser`.

## Contract layout

```text
app/bridge.odin   # declarations + implementations + _config metadata
```

```odin
@(odinbinder={
    name = "bridge",
    android_package = "dev.example.app",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}

@(export)                                   // Odin implements, platform calls
hello :: proc "c" () -> cstring {
    return cstring("Hello from Odin")
}

@(default_calling_convention="c")
foreign {
    @(odinbinder={direction="import", thread="ui"})  // platform implements, Odin calls
    show_toast :: proc(msg: cstring) ---
}
```

A body infers `export`; no body infers `import`. The explicit `direction`
attribute wins.

## Usage

```sh
odin build tools/odinbinder/src -o:speed -out:build/tools/odinbinder

build/tools/odinbinder generate --target all --spec app/bridge.odin \
  --header generated/shared/bridge.h \
  --kotlin generated/android/kotlin/dev/example/app/OdinBridge.kt \
  --jni generated/android/bridge_jni.c \
  --swift generated/ios/GameBridge.swift

build/tools/odinbinder check --spec app/bridge.odin
```

`--target android|ios|all`. One contract feeds the header, Kotlin/JNI, and
Swift; `--target all` writes every output. In this repo the
outputs are ignored and recreated by `odin run builder -- bindings`.

## Tests

```sh
odin run builder -- test
```

The fixture lives in `tools/odinbinder/tests/binding.odin`.

## Types

`i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool cstring`

Enums with an explicit `i32` or `u32` base are supported, and `Nullable_CString`
(alias of `cstring`) maps to optional strings. Nullable strings are currently
limited to import parameters.

Records, arrays, objects, callbacks, async, and `b32` are not supported yet.

## Rules

- Declarations use `proc "c"`.
- Imports cannot return `cstring` or `Nullable_CString`.
- The contract lives in `app/bridge.odin` and is compiled with the app, so app
  builds pass `-custom-attribute:odinbinder`.
