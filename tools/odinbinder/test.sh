#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
odin_bin=${ODIN:-odin}
tool="$root/build/tools/odinbinder"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/odinbinder-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$root/build/tools"
"$odin_bin" build "$root/tools/odinbinder/src" -o:speed -out:"$tool"

spec="$root/tools/odinbinder/tests/binding.odin"
"$tool" check --spec "$spec"
"$tool" generate --target all --spec "$spec" \
    --header "$tmp/bridge.h" \
    --kotlin "$tmp/Bridge.kt" \
    --jni "$tmp/bridge_jni.c" \
    --swift "$tmp/GameBridge.swift" \
    --quiet

check() {
    if ! grep -Fq "$1" "$2"; then
        echo "missing: $1" >&2
        echo "in: $2" >&2
        exit 1
    fi
}

check 'enum class Color(val value: Int)' "$tmp/Bridge.kt"
check 'Red(5)' "$tmp/Bridge.kt"
check 'Neg(-1)' "$tmp/Bridge.kt"
check '`object`(8)' "$tmp/Bridge.kt"
check 'default(9)' "$tmp/Bridge.kt"
check 'enum class Mode(val value: Int)' "$tmp/Bridge.kt"
check 'Max(-1)' "$tmp/Bridge.kt"
check 'fun showMessage(msg: String?)' "$tmp/Bridge.kt"
check 'fun pickColor(current: Int): Int' "$tmp/Bridge.kt"
check 'Color.fromValue(current)' "$tmp/Bridge.kt"
check 'Color.Red.value' "$tmp/Bridge.kt"
check 'private external fun nativeSetColor(color: Int)' "$tmp/Bridge.kt"
check 'fun `object`()' "$tmp/Bridge.kt"
check 'fun default()' "$tmp/Bridge.kt"

check 'public enum Color: Int32' "$tmp/GameBridge.swift"
check 'case red = 5' "$tmp/GameBridge.swift"
check 'case object = 8' "$tmp/GameBridge.swift"
check 'case `default` = 9' "$tmp/GameBridge.swift"
check 'public enum Mode: UInt32' "$tmp/GameBridge.swift"
check 'func showMessage(_ msg: String?)' "$tmp/GameBridge.swift"
check 'let msg_arg = msg.map { String(cString: $0) }' "$tmp/GameBridge.swift"
check 'Color.red.rawValue' "$tmp/GameBridge.swift"
check 'func object()' "$tmp/GameBridge.swift"
check 'func `default`()' "$tmp/GameBridge.swift"

check 'void set_color(int32_t color);' "$tmp/bridge.h"
check 'int32_t pick_color(int32_t current);' "$tmp/bridge.h"

check 'Java_dev_example_Bridge_nativeSetColor' "$tmp/bridge_jni.c"
check 'GetStaticMethodID(env, g_class, "object", "()V")' "$tmp/bridge_jni.c"
check 'Java_dev_example_Bridge_default' "$tmp/bridge_jni.c"
check 'g_mid_pickColor = (*env)->GetStaticMethodID(env, g_class, "pickColor", "(I)I");' "$tmp/bridge_jni.c"
check 'if (!env || !g_mid_pickColor) return 5;' "$tmp/bridge_jni.c"
check 'jstring jarg0 = msg ? (*env)->NewStringUTF(env, msg) : 0;' "$tmp/bridge_jni.c"
check 'if (jarg0) (*env)->DeleteLocalRef(env, jarg0);' "$tmp/bridge_jni.c"

# Implicit enum bases are 64-bit in Odin, so they must be rejected.
cat > "$tmp/bad_default.odin" <<'EOF'
package binding
E :: enum { A, B }
@(odinbinder={name="b", android_package="x", android_class="B", ios_module="B"})
_config :: struct {}
@(odinbinder={direction="import"})
f :: proc "c" (e: E)
EOF
if "$tool" check --spec "$tmp/bad_default.odin" >/dev/null 2>&1; then
    echo "expected implicit enum base to fail" >&2
    exit 1
fi

# Nullable strings are import parameters only.
cat > "$tmp/bad_nullable.odin" <<'EOF'
package binding
Nullable_CString :: cstring
@(odinbinder={name="b", android_package="x", android_class="B", ios_module="B"})
_config :: struct {}
@(odinbinder={direction="export"})
f :: proc "c" (msg: Nullable_CString)
EOF
if "$tool" check --spec "$tmp/bad_nullable.odin" >/dev/null 2>&1; then
    echo "expected nullable export to fail" >&2
    exit 1
fi

# Swift case collisions are rejected.
cat > "$tmp/bad_collision.odin" <<'EOF'
package binding
E :: enum i32 { Red, red }
@(odinbinder={name="b", android_package="x", android_class="B", ios_module="B"})
_config :: struct {}
@(odinbinder={direction="import"})
f :: proc "c" (e: E)
EOF
if "$tool" check --spec "$tmp/bad_collision.odin" >/dev/null 2>&1; then
    echo "expected Swift enum case collision to fail" >&2
    exit 1
fi

# Duplicate enum fields are rejected.
cat > "$tmp/bad_duplicate.odin" <<'EOF'
package binding
E :: enum i32 { A, A }
@(odinbinder={name="b", android_package="x", android_class="B", ios_module="B"})
_config :: struct {}
@(odinbinder={direction="import"})
f :: proc "c" (e: E)
EOF
if "$tool" check --spec "$tmp/bad_duplicate.odin" >/dev/null 2>&1; then
    echo "expected duplicate enum field to fail" >&2
    exit 1
fi

echo "odinbinder tests passed"
