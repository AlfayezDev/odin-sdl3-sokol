# Worked example: how `hello` travels from Odin to Kotlin and back

This walks the real files in this repo — open each path as you read.
Authoritative reference: [`BINDINGS.md`](../../BINDINGS.md).

## The contract file

`binding/spec/binding.odin` declares the API; it is parsed by odinbinder and is
not compiled into the app:

```odin
@(odinbinder={direction="export"})
hello :: proc "c" () -> cstring   // Odin implements, platform calls

@(odinbinder={direction="import"})
show_toast :: proc "c" (msg: cstring)   // platform implements, Odin calls
```

`binding/spec/binding.android.odin` and `binding/spec/binding.ios.odin` merge
over the shared file by name. Today both only override `show_toast` with the
right `thread` metadata.

Everything below is derived from those files by `odin run . -- bindings`.

## Direction 1 — Kotlin calls Odin (`hello`)

```
android: OdinBridge.hello()                        (OdinBridge.kt, generated external fun)
   └─ Java_dev_alfayez_odinsokol_OdinBridge_hello  (build/gen/bridge_jni.c, generated)
        └─ hello()                                 (app/bridge.odin, your Odin code)
```

iOS does the same without JNI: Swift calls the C symbol through
`@_silgen_name("hello")` inside the generated `binding/ios/GameBridge.swift`.

## Direction 2 — Odin calls Kotlin (`show_toast`)

```
odin: b.show_toast("hi")               (app/bridge.odin via libs:bridge foreign block)
   └─ show_toast(const char*)          (build/gen/bridge_jni.c, generated up-call)
        └─ OdinBridge.showToast("hi")  (OdinBridge.kt, generated wrapper)
             └─ PlatformHandler.showToast → Toast on the UI thread
```

iOS: `binding/ios/GameBridge.swift` generates the `@_cdecl("show_toast")`
entry point, and `binding/ios/BridgePlatform.swift` installs the handler that
shows a `UIAlertController`.

## Where each artifact goes

| Artifact | Path | Consumed by |
|---|---|---|
| C ABI header | `binding/api/bridge.h` | Swift bridging header, JNI glue, desktop stub |
| Odin foreign block | `vendors/bridge/bridge.odin` | the app (`libs:bridge`) |
| Kotlin bridge object | `binding/android/java/dev/alfayez/odinsokol/OdinBridge.kt` | the Activity |
| JNI glue | `build/gen/bridge_jni.c` (gitignored) | `libmain.so` link |
| Swift bridge | `binding/ios/GameBridge.swift` | Xcode target |

Platform bodies (the only hand-written non-Odin code):

| Import | Android | iOS | Desktop |
|---|---|---|---|
| `show_toast` | `PlatformHandler.showToast` → Toast | `BridgePlatform.swift` UIAlertController | `binding/desktop/bridge.c` printf |

## Lifecycle wiring (Android)

`binding/android/java/dev/alfayez/odinsokol/OdinsokolActivity.java`:

- `static { System.loadLibrary("main"); }` — loads the lib (and runs
  `JNI_OnLoad`, which caches the JavaVM + class + method IDs) before any
  bridge call
- `onCreate` installs an `OdinBridge.PlatformHandler` via
  `OdinBridge.setPlatform(...)`, and `onDestroy` clears it.
  It also logs `OdinBridge.hello()` / `OdinBridge.add(2, 3)`.

On the Odin side, `bridge_init()` in `app/bridge.odin` fires
`show_toast("hello from odin")` during app init — proving direction 2.
