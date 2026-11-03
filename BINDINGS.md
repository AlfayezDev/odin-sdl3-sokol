# Bindings — Odin ↔ Kotlin ↔ iOS

The cross-platform contract is one Odin file:

```text
binding/binding.odin
```

`tools/odinbinder` parses that file with Odin's own AST parser and emits the
C header, Odin foreign declarations, Kotlin/JNI, and Swift bindings. The
contract is parsed, not compiled into the app.

## The rule

```odin
// export = native implements, platform calls
@(odinbinder={direction="export"})
hello :: proc "c" () -> cstring

// import = platform implements, native calls
@(odinbinder={direction="import"})
show_toast :: proc "c" (msg: cstring)
```

A body on the declaration also infers `export`; a declaration without a body
infers `import`. The explicit `direction` attribute is recommended for clarity.

One contract produces the C header, Odin imports, Kotlin, JNI, and Swift. Run
all emitters with `--target all`, or one platform with `--target android|ios`.

## Metadata

```odin
@(odinbinder={
    name = "bridge",
    android_package = "dev.alfayez.odinsokol",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}
```

Per-function metadata:

```odin
@(odinbinder={direction="import", thread="ui"})
show_toast :: proc "c" (msg: cstring)
```

`thread="ui"` / `thread="main"` asks the generated platform wrapper to dispatch
on the UI/main thread. The shared contract uses `thread="ui"` for `show_toast`,
which works on both Android and iOS.

## Adding a binding — 2 steps

1. Declare it in `binding/binding.odin`:

   ```odin
   @(odinbinder={direction="export"})
   set_volume :: proc "c" (f: f32)
   ```

   Implement exports in `app/bridge.odin` as `proc "c"` functions.

2. Run:

   ```sh
   odin run . -- bindings
   ```

Every platform build also runs this automatically.

## What OdinBinder emits

These folders are ignored by git. Create them with `odin run . -- bindings`;
the desktop, Android, and iOS builds also run it automatically.

| Output | Consumed by |
|---|---|
| `binding/generated/bridge.h` | shared C ABI contract |
| `binding/generated/bridge/bridge.odin` | Odin app (`gen:bridge`) |
| `binding/android/generated/kotlin/.../OdinBridge.kt` | Android activity |
| `binding/android/generated/bridge_jni.c` | `libmain.so` link |
| `binding/ios/generated/GameBridge.swift` | Xcode target |

Generated files are grouped by platform:

```text
binding/generated/                  shared ABI
  bridge.h
  bridge/bridge.odin
binding/android/generated/          Android only
  bridge_jni.c
  kotlin/.../OdinBridge.kt
binding/ios/generated/              iOS only
  GameBridge.swift
```

Hand-written files stay outside these folders: `binding/binding.odin`,
`binding/android/android.yaml`, the Android activity, and `binding/ios/`
sources such as `entry.m`, `BridgePlatform.swift`, and `project.yaml`.

Current type support is intentionally small:

```text
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
bool
cstring
```

Records, enums, arrays, objects, callbacks, and async are the next layer.

## Platform implementations

- **Android**: the generated Kotlin object exposes a `PlatformHandler`. The
  activity installs it with `OdinBridge.setPlatform(...)`.
- **iOS**: the generated Swift enum exposes `OdinBridge.PlatformHandler`.
  `binding/ios/BridgePlatform.swift` installs it with
  `odinbinder_ios_install()`, called from `entry.m`.
- **Desktop**: no bridge backend for now; desktop builds run the app without the
  platform import calls.

## Type map

| Odin | C ABI | Kotlin | Swift |
|---|---|---|---|
| `i8/i16/i32/i64` | `intN_t` | `Byte/Short/Int/Long` | `Int8/Int16/Int32/Int64` |
| `u8/u16/u32/u64` | `uintN_t` | `UByte/UShort/UInt/ULong` | `UInt8/UInt16/UInt32/UInt64` |
| `f32/f64` | `float/double` | `Float/Double` | `Float/Double` |
| `bool` | `bool` | `Boolean` | `Bool` |
| `cstring` | `const char *` | `String` | `String` |

`b32` is intentionally not mapped yet; use `bool`.

## Convention checks

- Declarations must use `proc "c"`.
- Imports cannot return `cstring`.
- Declarations must be single-line. Grouped parameters like `(a, b: i32)` work.
- Returned `cstring` values are borrowed; the platform side must copy them
  before returning.
- If a tool compiles the contract file, pass `-custom-attribute:odinbinder`.

The binder is deliberately Odin-native: no YAML schema, no duplicate type
definitions, and the C header is derived from the same declarations the app
uses.
