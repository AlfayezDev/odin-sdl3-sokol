package app

// BINDINGS: every `proc "c"` declaration in this file is part of the
// cross-language API (bridgegen reads it — see BINDINGS.md):
//
//   with body    -> implemented here in Odin; consumed by Kotlin/Swift
//   without body -> implemented by the platform; callable from Odin
//
// The callable platform half is generated into libs:bridge (import it as
// `b` and call the proc directly).

import "core:c"
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

// ---- imports: platform -> odin ----

show_toast :: proc "c" (msg: cstring)

// ---- glue ----

// call once during app init: proves the odin -> platform direction
bridge_init :: proc() {
	b.show_toast("hello from odin")
}
