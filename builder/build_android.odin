package odin_sokol_build

// Android build.

import "core:fmt"
import "core:os"
import "core:strings"

SDL_ANDROID_ZIP :: "deps/SDL3-android-3.2.28.zip"
SDL_ANDROID_AAR :: "deps/SDL3-3.2.28.aar"

ensure_sdl_android_aar :: proc() {
	if os.is_file(SDL_ANDROID_AAR) do return
	sh("mkdir -p deps")
	if !sh("curl -fL https://github.com/libsdl-org/SDL/releases/download/release-3.2.28/SDL3-devel-3.2.28-android.zip -o " + SDL_ANDROID_ZIP) {
		fail("failed to download the SDL3 Android package")
	}
	sum_cmd := "sha256sum " + SDL_ANDROID_ZIP
	if !sh("command -v sha256sum >/dev/null") {
		sum_cmd = "shasum -a 256 " + SDL_ANDROID_ZIP
	}
	if !sh(fmt.tprintf("%s | grep -q ^d815aec61fa62e5e633a17410af70716a84bd5a302e2c39070ee471d31045590", sum_cmd)) {
		fail("SDL3 Android checksum mismatch")
	}
	if !sh(fmt.tprintf("unzip -p %s SDL3-3.2.28.aar > %s", SDL_ANDROID_ZIP, SDL_ANDROID_AAR)) {
		fail("failed to extract the SDL3 Android AAR")
	}
	sh("rm -f " + SDL_ANDROID_ZIP)
}

build_android :: proc(sample_id, smoke: i32) {
	gen_bindings()
	ensure_sdl_android_aar()

	ndk := os.get_env_alloc("ANDROID_NDK", context.allocator)
	if ndk == "" {
		sh(`
NDK=""
for d in "$HOME/Library/Android/sdk/ndk"/* "$HOME/Android/sdk/ndk"/*; do
  [ -d "$d" ] && NDK="$d"
done
printf '%s' "$NDK" > build/android_ndk_path
`)
		ndk = strings.trim_space(file_text("build/android_ndk_path"))
	}
	if ndk == "" {
		fail("Android NDK not found (set ANDROID_NDK)")
	}
	out_dir := fmt.tprintf("build/android/arm64-v8a")
	sh(fmt.tprintf("mkdir -p %s build/android/jni/arm64-v8a build/tools", out_dir))

	sdl_lib_dir := "build/android/sdl/arm64-v8a"
	sh(fmt.tprintf("mkdir -p %s", sdl_lib_dir))
	if !sh("unzip -p deps/SDL3-3.2.28.aar prefab/modules/SDL3-shared/libs/android.arm64-v8a/libSDL3.so > build/android/sdl/arm64-v8a/libSDL3.so") {
		fail("failed to extract libSDL3.so")
	}

	android_cc := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot",
		ndk, ndk,
	)

	// sokol headers (GLES3)
	sokol_objects(fmt.tprintf("%s/%s", root(), out_dir), "SOKOL_GLES3",
		fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -I%s/include", ndk, ndk, root()))

	// odin object
	if !sh(fmt.tprintf(
		"ODIN_ANDROID_NDK=%q ANDROID_NDK=%q odin build app %s -define:SMOKE_FRAMES=%d -define:SAMPLE_ID=%d -o:speed -target:linux_arm64 -subtarget:android -minimum-os-version:29 -build-mode:obj -no-entry-point -out:%s/odin-app.o",
		ndk, ndk, ODIN_COLLECTIONS, smoke, sample_id, out_dir,
	)) {
		fail("odin android object build failed")
	}

	sh("mkdir -p build/gen")
	if !sh(fmt.tprintf("%s -x c -c -O2 -Igenerated/shared %s -o build/gen/bridge_jni.o", android_cc, ANDROID_JNI)) {
		fail("bridge_jni.c compile failed")
	}

	// rename + link libmain.so
	llvm_objcopy := fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy", ndk)
	sh(fmt.tprintf("%s --redefine-sym sdl_main_provider=SDL_main %s/odin-app.o", llvm_objcopy, out_dir))
	link := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -shared -Wl,-soname,libmain.so -o %s/libmain.so %s/odin-app.o %s/obj/sokol_*.o build/gen/bridge_jni.o -L%s -lSDL3 -lEGL -lGLESv3 -llog -landroid -ldl -lm",
		ndk, ndk, out_dir, out_dir, out_dir, sdl_lib_dir,
	)
	if !sh(link) {
		fail("libmain.so link failed")
	}
	sh(fmt.tprintf("cp %s/libmain.so %s/libSDL3.so build/android/jni/arm64-v8a/", out_dir, sdl_lib_dir))

	// generate the gradle project from binding/android/android.yaml
	if !sh(fmt.tprintf("%s generate --spec %s --templates third_party/androidgen", ANDROIDGEN, ANDROID_SPEC)) {
		fail("androidgen generate failed")
	}

	if !sh("(cd build/android-project && ./gradlew --no-daemon :app:assembleDebug)") {
		fail("gradle assembleDebug failed")
	}
	if os.get_env_alloc("ANDROID_BUILD_ONLY", context.allocator) == "1" {
		fmt.println("ANDROID_BUILD_ONLY=1: packaged build/android-project/app/build/outputs/apk/debug/app-debug.apk, skipping install/launch")
		return
	}
	if !sh("adb install -r build/android-project/app/build/outputs/apk/debug/app-debug.apk") {
		fail("adb install failed")
	}
	sh("adb shell am force-stop dev.alfayez.odinsokol")
	if !sh("adb shell am start -n dev.alfayez.odinsokol/.OdinsokolActivity") {
		fail("adb launch failed")
	}
	fmt.println("launched dev.alfayez.odinsokol on device")
}
