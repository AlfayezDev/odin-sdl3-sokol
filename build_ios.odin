package odin_sokol_build

// iOS build.

import "core:fmt"

build_ios :: proc(sample_id, smoke: i32) {
	when ODIN_OS != .Darwin {
		fail("ios builds require macOS")
	}
	ensure_sdl_sources()
	gen_bindings()
	sh("mkdir -p build/ios")
	if !sh("xcodegen generate --spec binding/ios/project.yaml --project build/ios") {
		fail("xcodegen failed")
	}
	cmd := fmt.tprintf(
		"SAMPLE_ID=%d SMOKE_FRAMES=%d xcodebuild -project build/ios/OdinSokol.xcodeproj -scheme odin-sokol -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios-derived CODE_SIGNING_ALLOWED=NO ARCHS='$(uname -m)' build",
		sample_id, smoke,
	)
	if !sh(cmd) {
		fail("xcodebuild failed")
	}
	fmt.println("wrote build/ios-derived/Build/Products/Debug-iphonesimulator/odin-sokol.app")
}
