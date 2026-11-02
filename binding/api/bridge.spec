# bridge.spec — the single source of truth for Odin <-> platform bindings.
# Generate everything with: odin run . -- bridge
#
#   odin_*     implemented in Odin via @(export) in app/ (consumed by Kotlin
#              through JNI wrappers, by Swift/ObjC through this generated header)
#   platform_* implemented by the platform (Swift / Kotlin / desktop stub);
#              imported into Odin through vendors/bridge/bridge.odin
#
# types: string, int (i32), int64, bool, float (f32), double (f64)
# strings: returned pointers are borrowed; passed-in strings are copied.

package dev.alfayez.odinsokol
class OdinBridge

fn odin_hello() -> string
fn odin_add(a: int, b: int) -> int
fn platform_show_toast(msg: string)
