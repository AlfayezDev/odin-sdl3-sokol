package odin_sokol_build

// Desktop build.

import "core:fmt"
import "core:os"

build_desktop :: proc(sample_id, smoke: i32) {
	ensure_sdl_sources()

	mac := ODIN_OS == .Darwin
	sh("mkdir -p build/desktop")

	if mac {
		if !sh("command -v brew >/dev/null") || !sh("brew list sdl3 >/dev/null 2>&1") {
			fail("desktop on macOS needs SDL3: brew install sdl3")
		}
		gen_sdl_config("build/desktop/SDL_build_config.h",
			fmt.tprintf("%s/include/build_config/SDL_build_config.h.cmake", sdl_dir()),
			"SDL_VIDEO_DRIVER_COCOA SDL_VIDEO_OPENGL SDL_AUDIO_DRIVER_COREAUDIO SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_TIMER_UNIX SDL_FILESYSTEM_COCOA SDL_POWER_DARWIN SDL_LOADSO_DLOPEN SDL_LOCALE_COCOA SDL_MISC_COCOA SDL_DIALOG_COCOA SDL_TRAY_COCOA SDL_JOYSTICK_COCOA SDL_JOYSTICK_MFI SDL_SENSOR_COREMOTION SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HIDAPI_DISABLED SDL_CAMERA_DISABLED")
		sokol_objects("build/desktop", "SOKOL_GLCORE", "clang")
		linker := "-Wl,--start-group -Lbuild/desktop -lSDL3 build/desktop/obj/sokol_gfx.o build/desktop/obj/sokol_gl.o build/desktop/obj/sokol_debugtext.o build/desktop/obj/sokol_shape.o -Wl,--end-group -framework Cocoa -framework IOKit -framework Metal -framework CoreVideo -framework CoreAudio -framework CoreHaptics -framework GameController -framework CoreBluetooth -framework CoreMotion -framework AudioToolbox -framework QuartzCore -framework Foundation -ldl -lpthread -lm"
		if !sh(fmt.tprintf(
			"odin build app -collection:libs=vendors -define:SMOKE_FRAMES=%d -define:SAMPLE_ID=%d -o:speed -build-mode:exe -extra-linker-flags:\"%s\" -out:build/desktop/odin-sokol",
			smoke, sample_id, linker,
		)) {
			fail("desktop build failed")
		}
		fmt.println("wrote build/desktop/odin-sokol")
		return
	}

	// linux
	gen_sdl_config("build/desktop/SDL_build_config.h",
		fmt.tprintf("%s/include/build_config/SDL_build_config.h.cmake", sdl_dir()),
		"SDL_VIDEO_DRIVER_X11 SDL_VIDEO_DRIVER_DUMMY SDL_VIDEO_OPENGL SDL_VIDEO_OPENGL_GLX SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_THREAD_PTHREAD_RECURSIVE_MUTEX SDL_THREAD_PTHREAD_RECURSIVE_MUTEX_NP SDL_TIMER_UNIX SDL_TIME_UNIX SDL_FILESYSTEM_UNIX SDL_LOADSO_DLOPEN SDL_POWER_LINUX SDL_PROCESS_POSIX SDL_JOYSTICK_LINUX SDL_JOYSTICK_DUMMY SDL_DIALOG_DUMMY SDL_LOCALE_UNIX SDL_MISC_UNIX SDL_TRAY_UNIX SDL_STORAGE_GENERIC HAVE_X11_XLIB_H SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS SDL_INPUT_LINUXEV HAVE_LINUX_INPUT_H HAVE_CLOCK_GETTIME HAVE_LIBC HAVE_STDIO_H HAVE_STDLIB_H HAVE_STRING_H HAVE_STDDEF_H HAVE_ERRNO_H HAVE_MATH_H HAVE_LIMITS_H HAVE_INTTYPES_H HAVE_STDINT_H HAVE_STRINGS_H HAVE_SIGNAL_H HAVE_FLOAT_H HAVE_STDARG_H HAVE_CTYPE_H HAVE_TIME_H HAVE_SYS_TYPES_H HAVE_DLOPEN HAVE_GETENV SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HAPTIC_DISABLED SDL_HIDAPI_DISABLED SDL_SENSOR_DISABLED SDL_CAMERA_DISABLED SDL_FSOPS_POSIX SDL_HAPTIC_LINUX")
	sokol_objects("build/desktop", "SOKOL_GLCORE", "clang")
	_ = os.write_entire_file_from_string("build/desktop/sources.txt", fmt.tprintf("%s\n", sdl_sources_linux()))
	if !sh(fmt.tprintf(
		"ROOT=%q OUT_DIR=build/desktop CC=clang SDL_DIR=%q SOURCES_FILE=build/desktop/sources.txt sh sdl3_build.sh",
		root(), sdl_dir(),
	)) {
		fail("SDL3 source build failed")
	}
	sh("clang -x c -c -O2 -Ibinding/api binding/desktop/bridge.c -o build/desktop/bridge.o")
	sh("ar rcs build/desktop/libbridge.a build/desktop/bridge.o")
	linker := "-Wl,--start-group -Lbuild/desktop -lSDL3 -lbridge build/desktop/obj/sokol_gfx.o build/desktop/obj/sokol_gl.o build/desktop/obj/sokol_debugtext.o build/desktop/obj/sokol_shape.o -Wl,--end-group -lX11 -lXext -lGL -ldl -lpthread -lm"
	if !sh(fmt.tprintf(
		"odin build app -collection:libs=vendors -define:SMOKE_FRAMES=%d -define:SAMPLE_ID=%d -o:speed -build-mode:exe -extra-linker-flags:\"%s\" -out:build/desktop/odin-sokol",
		smoke, sample_id, linker,
	)) {
		fail("desktop build failed")
	}
	fmt.println("wrote build/desktop/odin-sokol")
	if !sh("./build/desktop/odin-sokol") {
		os.exit(1)
	}
}

sdl_sources_linux :: proc() -> string {
	return join([]string{
		"deps/SDL3-3.2.28/src/*.c",
		"deps/SDL3-3.2.28/src/atomic/*.c",
		"deps/SDL3-3.2.28/src/audio/*.c", "deps/SDL3-3.2.28/src/audio/dummy/*.c",
		"deps/SDL3-3.2.28/src/core/linux/SDL_threadprio.c",
		"deps/SDL3-3.2.28/src/core/linux/SDL_evdev.c",
		"deps/SDL3-3.2.28/src/core/linux/SDL_evdev_capabilities.c",
		"deps/SDL3-3.2.28/src/core/linux/SDL_evdev_kbd.c",
		"deps/SDL3-3.2.28/src/core/unix/SDL_poll.c", "deps/SDL3-3.2.28/src/core/unix/SDL_appid.c",
		"deps/SDL3-3.2.28/src/cpuinfo/*.c",
		"deps/SDL3-3.2.28/src/dialog/SDL_dialog.c", "deps/SDL3-3.2.28/src/dialog/SDL_dialog_utils.c", "deps/SDL3-3.2.28/src/dialog/unix/*.c",
		"deps/SDL3-3.2.28/src/dynapi/*.c",
		"deps/SDL3-3.2.28/src/events/*.c",
		"deps/SDL3-3.2.28/src/filesystem/SDL_filesystem.c", "deps/SDL3-3.2.28/src/filesystem/unix/*.c", "deps/SDL3-3.2.28/src/filesystem/posix/SDL_sysfsops.c",
		"deps/SDL3-3.2.28/src/gpu/*.c",
		"deps/SDL3-3.2.28/src/haptic/SDL_haptic.c", "deps/SDL3-3.2.28/src/haptic/linux/*.c",
		"deps/SDL3-3.2.28/src/hidapi/SDL_hidapi.c",
		"deps/SDL3-3.2.28/src/camera/SDL_camera.c", "deps/SDL3-3.2.28/src/camera/v4l2/*.c",
		"deps/SDL3-3.2.28/src/io/*.c", "deps/SDL3-3.2.28/src/io/generic/*.c",
		"deps/SDL3-3.2.28/src/joystick/*.c", "deps/SDL3-3.2.28/src/joystick/dummy/*.c", "deps/SDL3-3.2.28/src/joystick/linux/*.c",
		"deps/SDL3-3.2.28/src/libm/*.c",
		"deps/SDL3-3.2.28/src/loadso/dlopen/*.c",
		"deps/SDL3-3.2.28/src/locale/SDL_locale.c", "deps/SDL3-3.2.28/src/locale/unix/*.c",
		"deps/SDL3-3.2.28/src/main/SDL_main_callbacks.c", "deps/SDL3-3.2.28/src/main/SDL_runapp.c", "deps/SDL3-3.2.28/src/main/generic/SDL_sysmain_callbacks.c",
		"deps/SDL3-3.2.28/src/misc/SDL_url.c", "deps/SDL3-3.2.28/src/misc/unix/*.c",
		"deps/SDL3-3.2.28/src/power/SDL_power.c", "deps/SDL3-3.2.28/src/power/linux/*.c",
		"deps/SDL3-3.2.28/src/process/SDL_process.c", "deps/SDL3-3.2.28/src/process/posix/*.c",
		"deps/SDL3-3.2.28/src/render/SDL_render.c", "deps/SDL3-3.2.28/src/render/SDL_render_unsupported.c", "deps/SDL3-3.2.28/src/render/SDL_yuv_sw.c",
		"deps/SDL3-3.2.28/src/render/opengl/*.c", "deps/SDL3-3.2.28/src/render/opengles2/*.c", "deps/SDL3-3.2.28/src/render/software/*.c", "deps/SDL3-3.2.28/src/render/gpu/*.c",
		"deps/SDL3-3.2.28/src/sensor/SDL_sensor.c", "deps/SDL3-3.2.28/src/sensor/dummy/*.c",
		"deps/SDL3-3.2.28/src/stdlib/*.c",
		"deps/SDL3-3.2.28/src/storage/SDL_storage.c", "deps/SDL3-3.2.28/src/storage/generic/*.c",
		"deps/SDL3-3.2.28/src/thread/SDL_thread.c", "deps/SDL3-3.2.28/src/thread/pthread/*.c",
		"deps/SDL3-3.2.28/src/time/SDL_time.c", "deps/SDL3-3.2.28/src/time/unix/*.c",
		"deps/SDL3-3.2.28/src/timer/*.c", "deps/SDL3-3.2.28/src/timer/unix/*.c",
		"deps/SDL3-3.2.28/src/tray/SDL_tray_utils.c", "deps/SDL3-3.2.28/src/tray/dummy/SDL_tray.c", "deps/SDL3-3.2.28/src/tray/unix/*.c",
		"deps/SDL3-3.2.28/src/video/*.c", "deps/SDL3-3.2.28/src/video/dummy/*.c", "deps/SDL3-3.2.28/src/video/x11/*.c",
		"deps/SDL3-3.2.28/src/video/yuv2rgb/yuv_rgb_std.c", "deps/SDL3-3.2.28/src/video/yuv2rgb/yuv_rgb_sse.c",
		"deps/SDL3-3.2.28/src/core/SDL_core_unsupported.c",
	})
}
