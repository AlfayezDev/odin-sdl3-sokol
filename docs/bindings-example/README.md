# Worked example: how `hello` travels from Odin to Kotlin and back

This walks the real files in this repo — open each path as you read.
Authoritative reference: [`BINDINGS.md`](../../BINDINGS.md).

## The contract file

`binding/binding.odin` declares the API; it is parsed by odinbinder and is not
compiled into the app:

```odin
@(odinbinder={direction="export"})
hello :: proc "c" () -> cstring   // Odin implements, platform calls

@(odinbinder={direction="import"})
show_toast :: proc "c" (msg: cstring)   // platform implements, Odin calls
```

Everything below is derived from those files by `odin run . -- bindings`.
The generated folders are ignored by git; a clean checkout contains only the
hand-written contract and platform hosts.

## Direction 1 — Kotlin calls Odin (`hello`)

```
android: OdinBridge.hello()                        (generated Kotlin bridge)
   └─ Java_dev_alfayez_odinsokol_OdinBridge_hello  (binding/android/generated/bridge_jni.c)
        └─ hello()                                 (app/bridge.odin, your Odin code)
```

iOS does the same without JNI: Swift calls the C symbol through
`@_silgen_name("hello")` inside the generated
`binding/ios/generated/GameBridge.swift`.

## Direction 2 — Odin calls Kotlin (`show_toast`)

```
odin: b.show_toast("hi")               (app/bridge.odin via gen:bridge)
   └─ show_toast(const char*)          (binding/android/generated/bridge_jni.c)
        └─ OdinBridge.showToast("hi")  (generated Kotlin wrapper)
             └─ PlatformHandler.showToast → Toast on the UI thread
```

iOS: `binding/ios/generated/GameBridge.swift` generates the
`@_cdecl("show_toast")` entry point, and `binding/ios/BridgePlatform.swift`
installs the handler that shows a `UIAlertController`.

## Where each artifact goes

| Artifact | Path | Consumed by |
|---|---|---|
| C ABI header | `binding/generated/bridge.h` | JNI glue and ABI contract |
| Odin foreign block | `binding/generated/bridge/bridge.odin` | the app (`gen:bridge`) |
| Kotlin bridge object | `binding/android/generated/kotlin/dev/alfayez/odinsokol/OdinBridge.kt` | the Activity |
| JNI glue | `binding/android/generated/bridge_jni.c` | `libmain.so` link |
| Swift bridge | `binding/ios/generated/GameBridge.swift` | Xcode target |

Hand-written files stay outside the generated folders:

| File | Role |
|---|---|
| `binding/android/java/.../OdinsokolActivity.java` | installs the Android `PlatformHandler` |
| `binding/ios/BridgePlatform.swift` | installs the iOS `PlatformHandler` |
| `binding/ios/entry.m` | SDL app callbacks |
| `binding/ios/project.yaml` | XcodeGen spec |

Platform bodies:

| Import | Android | iOS |
|---|---|---|
| `show_toast` | `PlatformHandler.showToast` → Toast | `BridgePlatform.swift` → UIAlertController |

Desktop currently has no bridge backend; `bridge_init()` is compiled out there.

## Lifecycle wiring (Android)

`binding/android/java/dev/alfayez/odinsokol/OdinsokolActivity.java`:

- `static { System.loadLibrary("main"); }` — loads the lib (and runs
  `JNI_OnLoad`, which caches the JavaVM + class + method IDs) before any
  bridge call
- `onCreate` installs an `OdinBridge.PlatformHandler` via
  `OdinBridge.setPlatform(...)`, and `onDestroy` clears it.
  It also logs `OdinBridge.hello()` / `OdinBridge.add(2, 3)`.

On the Odin side, `bridge_init()` in `app/bridge.odin` fires
`show_toast("hello from odin")` on Android/iOS during app init — proving
direction 2.
