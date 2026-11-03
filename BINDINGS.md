# Bindings — Odin ↔ Kotlin ↔ iOS

The cross-platform contract lives in Odin files under `binding/spec/`:

```text
binding/spec/binding.odin           # shared
binding/spec/binding.android.odin   # Android overrides/additions
binding/spec/binding.ios.odin       # iOS overrides/additions
```

`tools/odinbinder` parses those files with Odin's own AST parser and emits the
C header, Odin foreign declarations, Kotlin/JNI, and Swift bindings. The spec
files are contracts, not compiled app code.

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

Target files are merged over the shared file by declaration name. With
`--target all`, the C header and Odin declarations are the union of every
target view; each platform's Kotlin/Swift output comes from its own merged
view.

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
on the UI/main thread where supported. `binding.android.odin` and
`binding.ios.odin` are the right place for platform-specific thread metadata.

## Adding a binding — 2 steps

1. Declare it in `binding/spec/binding.odin`, or in the target-specific file:

   ```odin
   @(odinbinder={direction="export"})
   set_volume :: proc "c" (f: f32)
   ```

   Implement exports in `app/bridge.odin` as `proc "c"` functions.

2. Run:

   ```sh
   odin run . -- bindings
   ```

The Android/iOS build commands also run this automatically.

## What OdinBinder emits

| Output | Consumed by |
|---|---|
| `binding/api/bridge.h` | C ABI contract |
| `vendors/bridge/bridge.odin` | Odin app (`libs:bridge`) |
| `binding/android/java/.../OdinBridge.kt` | Android activity |
| `build/gen/bridge_jni.c` | `libmain.so` link |
| `binding/ios/GameBridge.swift` | Xcode target |

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
- **Desktop**: `binding/desktop/bridge.c` implements imports for local runs.

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
- Platform files only override/add declarations; they do not replace the shared
  file.
- If a tool compiles the contract files, pass `-custom-attribute:odinbinder`.
  The three files also redeclare symbols by design, so compile them
  individually rather than as one package.

The binder is deliberately Odin-native: no YAML schema, no duplicate type
definitions, and the C header is derived from the same declarations the app
uses.
