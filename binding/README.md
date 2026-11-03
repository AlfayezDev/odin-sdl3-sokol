# Writing bindings

Only the files outside `generated/` are written by hand. The generated folders
are ignored by git and recreated by:

```sh
odin run . -- bindings
```

## 1. The contract

Declare the API in `binding/binding.odin`:

```odin
@(odinbinder={direction="export"})
hello :: proc "c" () -> cstring

@(odinbinder={direction="import", thread="ui"})
show_toast :: proc "c" (msg: cstring)
```

- `export` — Odin implements it, the platform calls it.
- `import` — the platform implements it, Odin calls it.
- `thread="ui"` — the generated wrapper dispatches to the main/UI thread, so
  platform handlers can be plain functions.

The `_config` record sets the generated names:

```odin
@(odinbinder={
    name = "bridge",
    android_package = "dev.alfayez.odinsokol",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}
```

## 2. Odin implementation

Exports are ordinary `proc "c"` functions in `app/bridge.odin`:

```odin
@(export)
hello :: proc "c" () -> cstring {
    return cstring("Hello from Odin")
}
```

Imports are callable through the generated `gen:bridge` package.

## 3. Android host

`binding/android/java/.../OdinsokolActivity.java` installs the generated
`PlatformHandler`:

```java
OdinBridge.setPlatform(new OdinBridge.PlatformHandler() {
    @Override
    public void showToast(String message) {
        Toast.makeText(OdinsokolActivity.this, message, Toast.LENGTH_SHORT).show();
    }
});
```

`OdinBridge` comes from `android_package` + `android_class`.

## 4. iOS host

`binding/ios/BridgePlatform.swift` installs the generated handler:

```swift
@_cdecl("odinbinder_ios_install")
public func odinbinder_ios_install() {
    OdinBridge.platform = OdinPlatform()
}
```

`OdinBridge` comes from `ios_module`. `entry.m` calls
`odinbinder_ios_install()` before the SDL app starts.

## Generated output

```text
binding/generated/                  shared C header + Odin imports
binding/android/generated/          Kotlin bridge + JNI glue
binding/ios/generated/              Swift bridge
```

Supported types: `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool cstring`.
Records, enums, arrays, objects, callbacks, async, and `b32` are not supported.
