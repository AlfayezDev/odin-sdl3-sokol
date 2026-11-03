# Bindings — Odin ↔ Kotlin ↔ iOS

One Odin file is the contract: **`app/bridge.odin`**. Every `proc "c"`
declaration in it is part of the cross-language API. The generic
**androidgen** tool (vendored under `tools/androidgen`) reads it through its
Odin adapter and generates all platform plumbing.

## The rule

```odin
hello :: proc "c" () -> cstring { ... }   // body = Odin implements it
show_toast :: proc "c" (msg: cstring)     // no body = the platform implements it
```

- **With a body** → an export. Callers: Kotlin gets
  `external fun hello()`, Swift calls it directly through the generated
  header.
- **Without a body** → an import. Implement it per platform (Swift
  `@_cdecl`, Kotlin `PlatformHandler`, or the desktop stub); Odin calls it
  through the generated foreign block (`libs:bridge`).

## Adding a binding — 2 steps

1. **Declare + implement** in `app/bridge.odin`:

   ```odin
   @(export)
   set_volume :: proc "c" (f: f32) {
       volume = f
   }
   ```

   (For imports, write the declaration without a body, then implement the
   platform side: Swift/Kotlin/desktop stub.)

2. **`odin run . -- bindings`** — done. All artifacts regenerate; the
   Android target also regenerates them automatically.

## What androidgen emits

| Output | Consumed by |
|---|---|
| `binding/api/bridge.h` — C ABI header | Swift bridging header, JNI glue, desktop stub |
| `vendors/bridge/bridge.odin` — foreign procs for imports | the app (`libs:bridge`) |
| `binding/android/java/.../OdinBridge.kt` — Kotlin bridge object | the Activity |
| `build/gen/bridge_jni.c` — JNI_OnLoad + wrappers + up-calls (gitignored) | `libmain.so` link |

The parity check is built in: an export *is* its implementation, so a
missing implementation is a compile error, not a silent runtime break.

## Type map

| odin     | C header        | Kotlin   | JNI      | sig                   |
|----------|-----------------|----------|----------|-----------------------|
| `cstring`| `const char *`  | `String` | `jstring`| `Ljava/lang/String;`  |
| `i32`    | `int32_t`       | `Int`    | `jint`   | `I`                   |
| `i64`    | `int64_t`       | `Long`   | `jlong`  | `J`                   |
| `b32`    | `int32_t`       | `Boolean`| `jboolean`| `Z`                  |
| `f32`    | `float`         | `Float`  | `jfloat` | `F`                   |
| `f64`    | `double`        | `Double` | `jdouble`| `D`                   |

## Conventions

- **String ownership**: returned `cstring` is borrowed (Odin owns it);
  passed-in strings are copied by the receiver.
- **Kotlin imports** go through the generated nested
  `OdinBridge.PlatformHandler`. Set `OdinBridge.platform` (or call
  `OdinBridge.setPlatform(...)` from Java) before native callbacks arrive.
- **iOS** has no generation: Swift imports the header via
  `binding/ios/Bridging.h` and implements imports with `@_cdecl`.
  `entry.m` is SDL C-entry machinery — keep it C, don't move it to Swift.
- **Grouped params** work: `add :: proc "c" (a, b: i32)` expands to two
  parameters.
- Declarations must be single-line. Export bodies open with `{` on the
  declaration line.

## Runtime flow (worked example)

See [`docs/bindings-example/README.md`](docs/bindings-example/README.md)
for the full walkthrough of how `hello` travels Kotlin → JNI wrapper →
Odin, and `show_toast` travels Odin → JNI up-call → Kotlin
`PlatformHandler` → Toast, with the generated symbol names at each hop.
