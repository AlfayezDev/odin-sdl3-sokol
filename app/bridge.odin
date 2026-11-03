package app

// The API contract lives in binding/binding.odin (see binding/README.md).
// Implement exports from that contract here as `proc "c"` functions.
// Imports are generated into gen:bridge (import it as `b` and call them).

import b "gen:bridge"

// ---- exports: odin -> kotlin/swift ----

@(export)
hello :: proc "c" () -> cstring {
	return cstring("Hello from Odin")
}

// ---- glue ----

// call once during app init: proves the odin -> platform direction
bridge_init :: proc() {
	when (ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET == .Android) || ODIN_PLATFORM_SUBTARGET_IOS {
		b.show_toast("hello from odin")
	}
}
