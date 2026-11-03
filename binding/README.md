# Writing bindings

Only the files outside `generated/` are written by hand. The generated folders
are ignored by git and recreated by:

```sh
odin run builder -- bindings
```

## 1. The bridge file

The contract and the Odin implementation live in `app/bridge.odin`:

```odin
@(odinbinder={
    name = "bridge",
    android_package = "dev.alfayez.odinsokol",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}

// export: Odin implements it, the platform calls it
@(export)
hello :: proc "c" () -> cstring {
    return cstring("Hello from Odin")
}

// import: the platform implements it, Odin calls it
@(default_calling_convention="c")
foreign {
    @(odinbinder={direction="import", thread="ui"})
    show_toast :: proc(msg: cstring) ---
}
```

- `export` — a real `proc "c"` with a body.
- `import` — a `foreign` declaration.
- `thread="ui"` — the generated wrapper dispatches to the main/UI thread.

Because the file contains odinbinder attributes, every app build passes:

```sh
-custom-attribute:odinbinder
```

## 2. Calling imports

Imports are called directly:

```odin
bridge_init :: proc() {
    when mobile {
        show_toast("hello from odin")
    }
}
```

No generated Odin package and no import alias.

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
generated/shared/bridge.h           shared C ABI header
generated/android/                  Kotlin bridge + JNI glue
generated/ios/                      Swift bridge
```

Supported types:

- `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool cstring`
- enums with an explicit `i32` or `u32` base
- `Nullable_CString :: cstring` for optional strings

Example enum:

```odin
Color :: enum i32 {
    Red,
    Green,
    Blue,
}

@(default_calling_convention="c")
foreign {
    @(odinbinder={direction="import", thread="ui"})
    set_color :: proc(color: Color) ---
}
```

Enums map to `enum class Color` in Kotlin and `enum Color: Int32`/`UInt32` in Swift.
Kotlin/Swift keyword field names are escaped; Swift case collisions are rejected.
Unsigned C types use the signed JVM type of the same width in Kotlin
(`u32` → `Int`), keeping the C/JNI bits unchanged.

Optional strings use the transparent alias:

```odin
Nullable_CString :: cstring
```

and are only supported on **import parameters**:

```odin
@(default_calling_convention="c")
foreign {
    @(odinbinder={direction="import", thread="ui"})
    show_message :: proc(msg: Nullable_CString) ---
}
```

They map to `String?` in Kotlin and Swift. Nullable returns and nullable export parameters are not supported yet.

Records, arrays, objects, callbacks, async, and `b32` are not supported.
