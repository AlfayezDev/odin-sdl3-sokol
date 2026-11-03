package odin_sokol_build

// Android build.

import "core:fmt"
import "core:os"
import "core:strings"

build_android :: proc(sample_id, smoke: i32) {
	ensure_sdl_sources()
	gen_bindings()

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

	gen_sdl_config(fmt.tprintf("%s/SDL_build_config.h", out_dir),
		fmt.tprintf("%s/include/build_config/SDL_build_config.h.cmake", sdl_dir()),
		"SDL_VIDEO_DRIVER_ANDROID SDL_VIDEO_OPENGL_EGL SDL_VIDEO_OPENGL_ES2 SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_TIMER_UNIX SDL_TIME_UNIX HAVE_LIBC HAVE_STDIO_H HAVE_STDLIB_H HAVE_STRING_H HAVE_STDDEF_H HAVE_ERRNO_H HAVE_SETENV HAVE_TIME_H HAVE_SYS_TYPES_H SDL_FILESYSTEM_ANDROID SDL_FSOPS_POSIX SDL_LOADSO_DLOPEN SDL_JOYSTICK_DISABLED SDL_DIALOG_DISABLED SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HAPTIC_DUMMY SDL_HIDAPI_DISABLED SDL_SENSOR_DUMMY SDL_CAMERA_DRIVER_ANDROID SDL_PROCESS_DUMMY SDL_CAMERA_DISABLED")

	sdl_list := join([]string{
		"deps/SDL3-3.2.28/src/*.c",
		"deps/SDL3-3.2.28/src/atomic/*.c",
		"deps/SDL3-3.2.28/src/audio/*.c", "deps/SDL3-3.2.28/src/audio/dummy/*.c",
		"deps/SDL3-3.2.28/src/core/android/SDL_android.c",
		"deps/SDL3-3.2.28/src/cpuinfo/*.c",
		"deps/SDL3-3.2.28/src/dialog/SDL_dialog.c", "deps/SDL3-3.2.28/src/dialog/SDL_dialog_utils.c",
		"deps/SDL3-3.2.28/src/dynapi/*.c",
		"deps/SDL3-3.2.28/src/events/*.c",
		"deps/SDL3-3.2.28/src/filesystem/SDL_filesystem.c", "deps/SDL3-3.2.28/src/filesystem/android/*.c",
		"deps/SDL3-3.2.28/src/filesystem/posix/SDL_sysfsops.c",
		"deps/SDL3-3.2.28/src/gpu/*.c",
		"deps/SDL3-3.2.28/src/haptic/SDL_haptic.c", "deps/SDL3-3.2.28/src/haptic/dummy/SDL_syshaptic.c",
		"deps/SDL3-3.2.28/src/hidapi/SDL_hidapi.c", "deps/SDL3-3.2.28/src/hidapi/android/hid.cpp",
		"deps/SDL3-3.2.28/src/camera/SDL_camera.c", "deps/SDL3-3.2.28/src/camera/android/SDL_camera_android.c",
		"deps/SDL3-3.2.28/src/io/*.c", "deps/SDL3-3.2.28/src/io/generic/*.c",
		"deps/SDL3-3.2.28/src/power/android/*.c", "deps/SDL3-3.2.28/src/sensor/dummy/SDL_dummysensor.c",
		"deps/SDL3-3.2.28/src/joystick/*.c", "deps/SDL3-3.2.28/src/joystick/dummy/*.c",
		"deps/SDL3-3.2.28/src/libm/*.c",
		"deps/SDL3-3.2.28/src/loadso/dlopen/*.c",
		"deps/SDL3-3.2.28/src/main/SDL_main_callbacks.c", "deps/SDL3-3.2.28/src/main/SDL_runapp.c", "deps/SDL3-3.2.28/src/main/generic/SDL_sysmain_callbacks.c",
		"deps/SDL3-3.2.28/src/misc/SDL_url.c", "deps/SDL3-3.2.28/src/misc/android/*.c",
		"deps/SDL3-3.2.28/src/power/SDL_power.c",
		"deps/SDL3-3.2.28/src/process/SDL_process.c", "deps/SDL3-3.2.28/src/process/dummy/*.c",
		"deps/SDL3-3.2.28/src/render/SDL_render.c", "deps/SDL3-3.2.28/src/render/SDL_render_unsupported.c", "deps/SDL3-3.2.28/src/render/SDL_yuv_sw.c",
		"deps/SDL3-3.2.28/src/render/opengles2/*.c", "deps/SDL3-3.2.28/src/render/software/*.c", "deps/SDL3-3.2.28/src/render/gpu/*.c",
		"deps/SDL3-3.2.28/src/sensor/SDL_sensor.c",
		"deps/SDL3-3.2.28/src/stdlib/*.c",
		"deps/SDL3-3.2.28/src/storage/SDL_storage.c", "deps/SDL3-3.2.28/src/storage/generic/*.c",
		"deps/SDL3-3.2.28/src/thread/SDL_thread.c", "deps/SDL3-3.2.28/src/thread/pthread/*.c",
		"deps/SDL3-3.2.28/src/time/SDL_time.c", "deps/SDL3-3.2.28/src/time/unix/*.c",
		"deps/SDL3-3.2.28/src/timer/*.c", "deps/SDL3-3.2.28/src/timer/unix/*.c",
		"deps/SDL3-3.2.28/src/tray/SDL_tray_utils.c", "deps/SDL3-3.2.28/src/tray/dummy/SDL_tray.c",
		"deps/SDL3-3.2.28/src/video/*.c", "deps/SDL3-3.2.28/src/video/android/*.c",
		"deps/SDL3-3.2.28/src/video/yuv2rgb/yuv_rgb_std.c",
		"deps/SDL3-3.2.28/src/core/SDL_core_unsupported.c",
	})
	_ = os.write_entire_file_from_string(fmt.tprintf("%s/sources.txt", out_dir), sdl_list)

	android_cc := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot",
		ndk, ndk,
	)
	if !sh(fmt.tprintf(
		"ROOT=%q OUT_DIR=%q CC=%q SDL_DIR=%q SOURCES_FILE=%s/sources.txt SHARED=1 LINK_LIBS=%q sh sdl3_build.sh",
		root(), out_dir, android_cc, sdl_dir(), out_dir, "-llog -landroid -lEGL -lGLESv3 -ldl -lm -lc++_static -lc++abi",
	)) {
		fail("SDL3 android build failed")
	}

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
	if !sh(fmt.tprintf("%s -x c -c -O2 -Ibinding/generated %s -o build/gen/bridge_jni.o", android_cc, ANDROID_JNI)) {
		fail("bridge_jni.c compile failed")
	}

	// rename + link libmain.so
	llvm_objcopy := fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy", ndk)
	sh(fmt.tprintf("%s --redefine-sym sdl_main_provider=SDL_main %s/odin-app.o", llvm_objcopy, out_dir))
	link := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -shared -Wl,-soname,libmain.so -o %s/libmain.so %s/odin-app.o %s/obj/sokol_*.o build/gen/bridge_jni.o -L%s -lSDL3 -lEGL -lGLESv3 -llog -landroid -ldl -lm",
		ndk, ndk, out_dir, out_dir, out_dir, out_dir,
	)
	if !sh(link) {
		fail("libmain.so link failed")
	}
	sh(fmt.tprintf("cp %s/libSDL3.so %s/libmain.so build/android/jni/arm64-v8a/", out_dir, out_dir))

	// generate the gradle project from binding/android/android.yaml
	if !sh(fmt.tprintf("%s generate --spec %s --project android --templates tools/androidgen", ANDROIDGEN, ANDROID_SPEC)) {
		fail("androidgen generate failed")
	}

	if !sh("(cd android && ./gradlew --no-daemon :app:assembleDebug)") {
		fail("gradle assembleDebug failed")
	}
	if os.get_env_alloc("ANDROID_BUILD_ONLY", context.allocator) == "1" {
		fmt.println("ANDROID_BUILD_ONLY=1: packaged android/app/build/outputs/apk/debug/app-debug.apk, skipping install/launch")
		return
	}
	if !sh("adb install -r android/app/build/outputs/apk/debug/app-debug.apk") {
		fail("adb install failed")
	}
	sh("adb shell am force-stop dev.alfayez.odinsokol")
	if !sh("adb shell am start -n dev.alfayez.odinsokol/.OdinsokolActivity") {
		fail("adb launch failed")
	}
	fmt.println("launched dev.alfayez.odinsokol on device")
}
