package odin_sokol_build

// Unified build orchestrator. Usage:
//   odin run . -- tools      (build odinbinder + androidgen, verify sokol-shdc)
//   odin run . -- shaders    (sokol-shdc -> vendors/shaders)
//   odin run . -- bindings   (odinbinder -> C/Odin/Kotlin/JNI/Swift bridge)
//   odin run . -- android    [ANDROID_BUILD_ONLY=1]
//   odin run . -- ios        (macOS only: xcodegen + xcodebuild simulator build)
// Env: ANDROID_NDK, ANDROID_BUILD_ONLY.

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

foreign {
	system :: proc "c" (command: cstring) -> c.int ---
}

ANDROIDGEN :: "build/tools/androidgen"
ODINBINDER :: "build/tools/odinbinder"
ANDROID_SPEC :: "binding/android/android.yaml"
BINDING_SPEC :: "binding"
BRIDGE_HEADER :: "binding/generated/bridge.h"
BRIDGE_ODIN :: "binding/generated/bridge/bridge.odin"
ANDROID_KOTLIN :: "binding/android/generated/kotlin/dev/alfayez/odinsokol/OdinBridge.kt"
ANDROID_JNI :: "binding/android/generated/bridge_jni.c"
IOS_SWIFT :: "binding/ios/generated/GameBridge.swift"
ODIN_COLLECTIONS :: "-collection:libs=vendors -collection:gen=binding/generated"

main :: proc() {
	target := ""
	args := os.args
	if len(args) > 1 {
		target = args[1]
	}

	sh("mkdir -p build")

	switch target {
	case "android":
		build_android()
	case "ios":
		build_ios()
	case "shaders":
		run_shaders()
	case "bindings":
		gen_bindings()
	case "tools":
		ensure_tools()
	case:
		if target != "" do fmt.eprintln("unknown target:", target)
		fmt.eprintln("usage: odin run . -- [android|ios|shaders|bindings|tools]")
		os.exit(1)
	}
}

// Helpers

sh :: proc(cmd: string) -> bool {
	cs := strings.clone_to_cstring(cmd, context.temp_allocator)
	status := system(cs)
	if status != 0 {
		fmt.eprintln("FAILED:", cmd)
	}
	return status == 0
}

find :: proc(s, sub: string) -> i32 {
	if len(sub) == 0 || len(sub) > len(s) {
		return -1
	}
	for i in 0 ..= len(s) - len(sub) {
		if s[i:i + len(sub)] == sub {
			return i32(i)
		}
	}
	return -1
}

fail :: proc(msg: string) {
	fmt.eprintln("error:", msg)
	os.exit(1)
}

root :: proc() -> string {
	p := os.get_env_alloc("PWD", context.allocator)
	if p == "" {
		return "."
	}
	return p
}

join :: proc(parts: []string) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	for p in parts {
		strings.write_string(&b, p)
		strings.write_rune(&b, '\n')
	}
	return strings.to_string(b)
}

file_text :: proc(path: string) -> string {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return ""
	}
	return string(data)
}

sdl_dir :: proc() -> string {
	return "deps/SDL3-3.2.28"
}
