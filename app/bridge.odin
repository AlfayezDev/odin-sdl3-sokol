package app

// This file is both the bridge contract and the Odin implementation.
// Exports have real bodies. Imports are `foreign` declarations.
// OdinBinder parses this file to generate the platform bridge code.

@(odinbinder={
    name = "bridge",
    android_package = "dev.alfayez.odinsokol",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}

// Optional strings map to String? in Kotlin and Swift.
Nullable_CString :: cstring

// ---- exports: odin -> platform ----

@(export)
hello :: proc "c" () -> cstring {
	return cstring("Hello from Odin")
}

// ---- imports: platform -> odin ----

@(default_calling_convention="c")
foreign {
	@(odinbinder={direction="import", thread="ui"})
	show_toast :: proc(msg: cstring) ---
}

// ---- glue ----

// call once during app init: proves the odin -> platform direction
bridge_init :: proc() {
	when (ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET == .Android) || ODIN_PLATFORM_SUBTARGET_IOS {
		show_toast("hello from odin")
	}
}
