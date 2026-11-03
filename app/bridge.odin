package app

// BINDINGS: the API contract lives in binding/spec/*.odin (see BINDINGS.md).
// Implement exports from that contract here as `proc "c"` functions.
// Imports are generated into libs:bridge (import it as `b` and call them).

import b "libs:bridge"

// ---- exports: odin -> kotlin/swift ----

@(export)
hello :: proc "c" () -> cstring {
	return cstring("Hello from Odin")
}

@(export)
add :: proc "c" (a, b: i32) -> i32 {
	return a + b
}

// ---- glue ----

// call once during app init: proves the odin -> platform direction
bridge_init :: proc() {
	b.show_toast("hello from odin")
}
