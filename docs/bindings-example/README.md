# Worked example: how `hello` travels from Odin to Kotlin and back

This walks the real files in this repo — open each path as you read.
Authoritative reference: [`BINDINGS.md`](../../BINDINGS.md).

## The contract file

`app/bridge.odin` is both the API spec and the Odin implementation:

```odin
@(export)
hello :: proc "c" () -> cstring { ... }   // body → Odin implements it

show_toast :: proc "c" (msg: cstring)     // no body → the platform implements it
```

Everything below is derived from that file by `odin run . -- bindings`.

## Direction 1 — Kotlin calls Odin (`hello`)

```
android: OdinBridge.hello()                        (OdinBridge.kt, generated external fun)
   └─ Java_dev_alfayez_odinsokol_OdinBridge_hello  (build/gen/bridge_jni.c, generated)
        └─ hello()                                 (app/bridge.odin, your Odin code)
```

iOS does the same without JNI: Swift calls `odin_hello` — the C symbol
from the generated `binding/api/bridge.h`, imported through
`binding/ios/Bridging.h`.

## Direction 2 — Odin calls Kotlin (`show_toast`)

```
odin: b.show_toast("hi")               (app/bridge.odin via libs:bridge foreign block)
   └─ show_toast(const char*)          (build/gen/bridge_jni.c, generated up-call)
        └─ OdinBridge.showToast("hi")  (OdinBridge.kt, generated wrapper)
             └─ PlatformHandler.showToast → Toast on the UI thread
```

iOS: `binding/ios/bridge.swift` implements the same C symbol with
`@_cdecl` and shows a UIAlertController.

## Where each artifact goes

| Artifact | Path | Consumed by |
|---|---|---|
| C ABI header | `binding/api/bridge.h` | Swift bridging header, JNI glue, desktop stub |
| Odin foreign block | `vendors/bridge/bridge.odin` | the app (`libs:bridge`) |
| Kotlin bridge object | `binding/android/java/dev/alfayez/odinsokol/OdinBridge.kt` | the Activity |
| JNI glue | `build/gen/bridge_jni.c` (gitignored) | `libmain.so` link |

Platform bodies (the only hand-written non-Odin code):

| Import | Android | iOS | Desktop |
|---|---|---|---|
| `show_toast` | `PlatformHandler.showToast` → Toast | `bridge.swift` UIAlertController | `binding/desktop/bridge.c` printf |

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
