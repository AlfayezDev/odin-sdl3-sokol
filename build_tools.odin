package odin_sokol_build

// Tool bootstrap and binding generation.

import "core:fmt"

ensure_tools :: proc() {
	sh("mkdir -p build/tools")
	if !sh(fmt.tprintf("odin build tools/androidgen/src -o:speed -out:%s", ANDROIDGEN)) {
		fail("androidgen build failed")
	}
	if !sh(fmt.tprintf("odin build tools/odinbinder/src -o:speed -out:%s", ODINBINDER)) {
		fail("odinbinder build failed")
	}
	shdc := shdc_path()
	if !sh(fmt.tprintf("test -x %q", shdc)) {
		fail(fmt.tprintf("sokol-shdc missing at %s (run tools/sokol-shdc/fetch.sh or add the platform binary)", shdc))
	}
}

shdc_path :: proc() -> string {
	when ODIN_OS == .Linux {
		return "tools/sokol-shdc/bin/linux-x86_64/sokol-shdc"
	} else when ODIN_OS == .Darwin {
		when ODIN_ARCH == .arm64 {
			return "tools/sokol-shdc/bin/macos-arm64/sokol-shdc"
		} else {
			return "tools/sokol-shdc/bin/macos-x86_64/sokol-shdc"
		}
	} else when ODIN_OS == .Windows {
		return "tools/sokol-shdc/bin/windows-x86_64/sokol-shdc.exe"
	}
	return "tools/sokol-shdc/bin/sokol-shdc"
}

// regenerate the cross-platform binding artifacts from binding/spec/*.odin
gen_bindings :: proc() {
	ensure_tools()
	if !sh(fmt.tprintf(
		"%s generate --target all --spec %s --header %s --odin %s --kotlin %s --jni %s --swift %s --quiet",
		ODINBINDER, BINDING_SPEC, BRIDGE_HEADER, BRIDGE_ODIN, ANDROID_KOTLIN, ANDROID_JNI, IOS_SWIFT,
	)) {
		fail("odinbinder failed")
	}
	fmt.println("bindings regenerated: binding/generated and platform generated folders")
}
