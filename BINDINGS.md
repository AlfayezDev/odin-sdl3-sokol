# Bindings — Odin ↔ Kotlin ↔ iOS

One spec file is the contract. Everything else is generated.

```
binding/api/bridge.spec    # ← the only thing you edit
```

`bridgegen` (vendored under `tools/bridgegen`) emits all four artifacts:

| Output | Consumed by |
|---|---|
| `binding/api/bridge.h` — C ABI header | Swift (bridging header), JNI glue, desktop stub |
| `vendors/bridge/bridge.odin` — Odin `foreign` procs | the app (`libs:bridge`) |
| `binding/android/java/.../OdinBridge.kt` — Kotlin bridge object | the Activity |
| `build/gen/bridge_jni.c` — JNI_OnLoad + wrappers + up-calls (gitignored) | `libmain.so` link |

Regenerate: `odin run . -- bridge` (the android target runs it automatically).

## Adding a binding — 3 steps

1. **Declare** in `binding/api/bridge.spec`:

   ```
   fn odin_set_volume(f: float)
   ```

   - `odin_*` → implemented in Odin, called by platforms
   - `platform_*` → implemented on the platform, called by Odin

2. **Implement the logic**:

   ```odin
   // app/bridge.odin
   @(export)
   odin_set_volume :: proc "c" (f: f32) {
       volume = f
   }
   ```

   For `platform_*` you implement the platform side instead — Swift
   (`@_cdecl("platform_…")`), Kotlin (`onPlatformEvent` dispatcher), or the
   desktop stub.

3. **`odin run . -- bridge`** — done. The parity check warns if a spec'd
   `odin_*` function has no matching `@(export)` proc in `app/`.

## Spec types → per-language map

| spec     | C header   | Odin   | Kotlin  | JNI      | sig                   |
|----------|------------|--------|---------|----------|-----------------------|
| `string` | `const char *` | `cstring` | `String`  | `jstring`  | `Ljava/lang/String;` |
| `int`    | `int32_t`  | `i32`  | `Int`   | `jint`   | `I`                   |
| `int64`  | `int64_t`  | `i64`  | `Long`  | `jlong`  | `J`                   |
| `float`  | `float`    | `f32`  | `Float` | `jfloat` | `F`                   |
| `double` | `double`   | `f64`  | `Double`| `jdouble`| `D`                   |
| `bool`   | `bool`     | `b32`  | `Boolean`| `jboolean`| `Z`                 |

## Conventions

- `odin_*` / `platform_*` prefixes decide direction — nothing else does.
- Returned `string` is **borrowed** (Odin owns it, never freed by the caller);
  passed-in strings are copied by the receiver.
- Kotlin-side dispatch: generated `platform_*` funs forward to
  `onPlatformEvent(name, args)` on the UI thread — put platform behavior
  in that `when` (it's committed glue, edit freely).
- iOS has no generation at all: Swift imports the generated header through
  `binding/ios/Bridging.h` and implements `platform_*` with `@_cdecl`.
  `entry.m` is SDL C-entry machinery — not bindings, don't move it to Swift.
