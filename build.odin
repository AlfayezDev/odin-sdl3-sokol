package odin_sokol_build

// Unified build orchestrator. Usage:
//   odin run . --            (desktop, default)
//   odin run . -- desktop
//   odin run . -- android    [SAMPLE_ID=2] [SMOKE_FRAMES=0]
//   odin run . -- ios        (macOS only: xcodegen + xcodebuild simulator build)
// Env: SAMPLE_ID, SMOKE_FRAMES, ANDROID_NDK, ADB.

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

foreign {
	system :: proc "c" (command: cstring) -> c.int ---
}

main :: proc() {
	target := "desktop"
	args := os.args
	if len(args) > 1 {
		target = args[1]
	}
	sample_id := env_int("SAMPLE_ID", 0)
	smoke := env_int("SMOKE_FRAMES", 0)

	sh("mkdir -p build")
	ensure_sdl_sources()

	switch target {
	case "desktop":
		build_desktop(sample_id, smoke)
	case "android":
		build_android(sample_id, smoke)
	case "ios":
		build_ios(sample_id, smoke)
	case:
		fmt.eprintln("unknown target:", target)
		fmt.eprintln("usage: odin run . -- [desktop|android|ios]")
		os.exit(1)
	}
}

// ------------------------------------------------------------ helpers

sh :: proc(cmd: string) -> bool {
	cs := strings.clone_to_cstring(cmd, context.temp_allocator)
	status := system(cs)
	if status != 0 {
		fmt.eprintln("FAILED:", cmd)
	}
	return status == 0
}

env_int :: proc(name: string, fallback: i32) -> i32 {
	v := os.get_env_alloc(name, context.allocator)
	if v == "" {
		return fallback
	}
	n: i32
	for ch in v {
		if ch < '0' || ch > '9' {
			return fallback
		}
		n = n * 10 + i32(ch - '0')
	}
	return n
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

gen_sdl_config :: proc(out_path, template_path: string, defines_csv: string) {
	defines: map[string]bool
	defines = make(map[string]bool)
	for d in strings.split(defines_csv, " ") {
		if d != "" do defines[d] = true
	}
	data, err := os.read_entire_file_from_path(template_path, context.allocator)
	if err != nil {
		fail(fmt.tprintf("missing %s", template_path))
	}
	b: strings.Builder
	strings.builder_init(&b)
	for line in strings.split(string(data), "\n") {
		s := strings.trim_space(line)
		if strings.has_prefix(s, "#cmakedefine ") {
			name := strings.trim_space(s[len("#cmakedefine"):])
			if defines[name] {
				fmt.sbprintf(&b, "#define %s 1\n", name)
			} else {
				fmt.sbprintf(&b, "/* #undef %s */\n", name)
			}
		} else if strings.has_prefix(s, "#cmakedefine01 ") {
			name := strings.trim_space(s[len("#cmakedefine01"):])
			v := i32(0)
			if defines[name] do v = 1
			fmt.sbprintf(&b, "#define %s %d\n", name, v)
		} else {
			fmt.sbprintf(&b, "%s\n", line)
		}
	}
	txt := strings.to_string(b)
	// strip @VAR@ markers (single-line pairs)
	for strings.contains(txt, "@") {
		i := find(txt, "@")
		j := find(txt[i + 1:], "@") + i32(i) + 1
		txt = fmt.tprintf("%s%s", txt[:i], txt[j + 1:])
	}
	_ = os.write_entire_file_from_string(out_path, txt)
}

ensure_sdl_sources :: proc() {
	if sh("test -d deps/SDL3-3.2.28") {
		return
	}
	sh("mkdir -p deps")
	if !sh("curl -fL https://github.com/libsdl-org/SDL/releases/download/release-3.2.28/SDL3-3.2.28.tar.gz -o deps/SDL3.tar.gz") {
		fail("failed to download SDL3-3.2.28 tarball")
	}
	// checksum + extract
	check := "#!/bin/sh\npython3 - <<'PY'\nimport hashlib, sys\ndata = open('deps/SDL3.tar.gz', 'rb').read()\nif hashlib.sha256(data).hexdigest() != '1330671214d146f8aeb1ed399fc3e081873cdb38b5189d1f8bb6ab15bbc04211':\n    sys.exit('SDL checksum mismatch')\nPY\n"
	_ = os.write_entire_file_from_string("deps/check_sdl.sh", check)
	if !sh("sh deps/check_sdl.sh") {
		fail("SDL checksum mismatch")
	}
	if !sh("tar xf deps/SDL3.tar.gz -C deps && rm -f deps/SDL3.tar.gz deps/check_sdl.sh") {
		fail("failed to extract SDL3 tarball")
	}
}

sokol_objects :: proc(out_dir: string, backend, cc: string) {
	units := [4]string{"gfx", "gl", "debugtext", "shape"}
	sh(fmt.tprintf("mkdir -p %s/obj", out_dir))
	for unit in units {
		flags := ""
		if unit == "gfx" {
			flags = "-DSOKOL_IMPL -include sokol_log.h"
		} else {
			flags = fmt.tprintf("-DSOKOL_%s_IMPL -include sokol_gfx.h", strings.to_upper(unit))
		}
		cmd := fmt.tprintf(
			"%s -x c -c -O2 -DSOKOL_NO_ENTRY -D%s %s -I%s/include %s/include/%s -o %s/obj/sokol_%s.o",
			cc, backend, flags, out_dir, sdl_dir(), unit, out_dir, unit,
		)
		if !sh(cmd) {
			fail(fmt.tprintf("sokol %s header compile failed", unit))
		}
	}
}

join :: proc(parts: []string) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	for p in parts {
		strings.write_string(&b, p)
		strings.write_rune(&b, ' ')
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

// ------------------------------------------------------------ desktop

build_desktop :: proc(sample_id, smoke: i32) {
	mac := ODIN_OS == .Darwin
	sh("mkdir -p build/desktop")

	if mac {
		if !sh("command -v brew >/dev/null") || !sh("brew list sdl3 >/dev/null 2>&1") {
			fail("desktop on macOS needs SDL3: brew install sdl3")
		}
		gen_sdl_config("build/desktop/SDL_build_config.h",
			fmt.tprintf("%s/include/build_config/SDL_build_config.h.cmake", sdl_dir()),
			"SDL_VIDEO_DRIVER_COCOA SDL_VIDEO_OPENGL SDL_AUDIO_DRIVER_COREAUDIO SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_TIMER_UNIX SDL_FILESYSTEM_COCOA SDL_POWER_DARWIN SDL_LOADSO_DLOPEN SDL_LOCALE_COCOA SDL_MISC_COCOA SDL_DIALOG_COCOA SDL_TRAY_COCOA SDL_JOYSTICK_COCOA SDL_JOYSTICK_MFI SDL_SENSOR_COREMOTION SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HIDAPI_DISABLED SDL_CAMERA_DISABLED")
		sokol_objects("build/desktop", "SOKOL_GLCORE", "clang -Ideps/SDL3-3.2.28/include")
		linker := "-Wl,--start-group -Lbuild/desktop -lSDL3 build/desktop/obj/sokol_*.o -Wl,--end-group -framework Cocoa -framework IOKit -framework Metal -framework CoreVideo -framework CoreAudio -framework CoreHaptics -framework GameController -framework CoreBluetooth -framework CoreMotion -framework AudioToolbox -framework QuartzCore -framework Foundation -ldl -lpthread -lm"
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
		"SDL_VIDEO_DRIVER_X11 SDL_VIDEO_DRIVER_DUMMY SDL_VIDEO_OPENGL SDL_VIDEO_OPENGL_GLX SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_THREAD_PTHREAD_RECURSIVE_MUTEX SDL_THREAD_PTHREAD_RECURSIVE_MUTEX_NP SDL_TIMER_UNIX SDL_FILESYSTEM_UNIX SDL_LOADSO_DLOPEN SDL_POWER_LINUX SDL_PROCESS_POSIX SDL_JOYSTICK_LINUX SDL_JOYSTICK_DUMMY SDL_DIALOG_DUMMY SDL_LOCALE_UNIX SDL_MISC_UNIX SDL_TRAY_UNIX SDL_STORAGE_GENERIC HAVE_X11_XLIB_H SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS SDL_INPUT_LINUXEV HAVE_LINUX_INPUT_H HAVE_CLOCK_GETTIME HAVE_LIBC HAVE_STDIO_H HAVE_STDLIB_H HAVE_STRING_H HAVE_STDDEF_H HAVE_ERRNO_H HAVE_MATH_H HAVE_LIMITS_H HAVE_INTTYPES_H HAVE_STDINT_H HAVE_STRINGS_H HAVE_SIGNAL_H HAVE_FLOAT_H HAVE_STDARG_H HAVE_CTYPE_H HAVE_TIME_H HAVE_SYS_TYPES_H HAVE_DLOPEN HAVE_GETENV SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HAPTIC_DISABLED SDL_HIDAPI_DISABLED SDL_SENSOR_DISABLED SDL_CAMERA_DISABLED SDL_FSOPS_POSIX")
	sokol_objects("build/desktop", "SOKOL_GLCORE", "clang")
	if !sh(fmt.tprintf(
		"cd %s && bash -c 'set -e; : > objs.txt; while read -r f; do o=\"build/desktop/obj/$(printf %%s \"${f#deps/SDL3-3.2.28/}\" | tr / _).o\"; echo \"$o $ROOT/$f\" >> objs.txt; done < build/desktop/sources.txt; cat objs.txt | xargs -P \"$(nproc)\" -L1 sh -c '\"$0\" -x c -c -O2 -fPIC -I\"build/desktop\" -I\"deps/SDL3-3.2.28/include\" -I\"deps/SDL3-3.2.28/src\" \"$2\" -o \"$1\"' _ \"clang\"; ar rcs build/desktop/libSDL3.a build/desktop/obj/*.o'",
		root(),
	)) {
		fail("SDL3 source build failed")
	}
	linker := "-Wl,--start-group -Lbuild/desktop -lSDL3 build/desktop/obj/sokol_*.o -Wl,--end-group -lX11 -lXext -lGL -ldl -lpthread -lm"
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
		"deps/SDL3-3.2.28/src/dialog/SDL_dialog.c", "deps/SDL3-3.2.28/src/dialog/SDL_dialog_utils.c",
		"deps/SDL3-3.2.28/src/dynapi/*.c",
		"deps/SDL3-3.2.28/src/events/*.c",
		"deps/SDL3-3.2.28/src/filesystem/SDL_filesystem.c", "deps/SDL3-3.2.28/src/filesystem/posix/*.c",
		"deps/SDL3-3.2.28/src/gpu/*.c",
		"deps/SDL3-3.2.28/src/haptic/SDL_haptic.c",
		"deps/SDL3-3.2.28/src/hidapi/SDL_hidapi.c",
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

build_sdl3_sources :: proc(platform, out_dir, cc: string) {
	list := ""
	if platform == "linux" {
		list = sdl_sources_linux()
	} else {
		fail(fmt.tprintf("sdl source build for %s not supported", platform))
	}
	list_file := fmt.tprintf("%s/sources.txt", out_dir)
	_ = os.write_entire_file_from_string(list_file, list)
	// shell: compile in parallel, then archive
	script := fmt.tprintf(
		`cd "$ROOT"
: > "%s/objs.txt"
while read -r f; do
  o="%s/obj/$(printf %%s "${f#deps/SDL3-3.2.28/}" | tr / _).o"
  echo "$o $ROOT/$f" >> "%s/objs.txt"
done < "%s"
cat "%s/objs.txt" | xargs -P "$(sysctl -n hw.ncpu 2>/dev/null || nproc)" -L1 sh -c '$0 -x c -c -O2 -fPIC -I"%s" -I"$SDLDIR/include" -I"$SDLDIR/src" "$2" -o "$1"' _ "$CC"
`,
		out_dir, out_dir, out_dir, list_file, out_dir, out_dir,
	)
	_ = os.write_entire_file_from_string(fmt.tprintf("%s/compile.sh", out_dir), fmt.tprintf("#!/bin/sh\nROOT=%q\nCC=%q\nSDLDIR=%q\n%s", root(), cc, sdl_dir(), script))
	if !sh(fmt.tprintf("ROOT=%q CC=%q SDLDIR=%q sh %s/compile.sh", root(), cc, sdl_dir(), out_dir)) {
		fail("SDL3 source build failed")
	}
}

// ------------------------------------------------------------ android

build_android :: proc(sample_id, smoke: i32) {
	if !sh("test -d android/app") {
		if !sh("python3 scripts/generate-android.py") {
			fail("android scaffold generation failed")
		}
	}
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
	sh(fmt.tprintf("mkdir -p %s android/app/src/main/jniLibs/arm64-v8a", out_dir))

	gen_sdl_config(fmt.tprintf("%s/SDL_build_config.h", out_dir),
		fmt.tprintf("%s/include/build_config/SDL_build_config.h.cmake", sdl_dir()),
		"SDL_VIDEO_DRIVER_ANDROID SDL_VIDEO_OPENGL_EGL SDL_AUDIO_DRIVER_DUMMY SDL_THREAD_PTHREAD SDL_TIMER_UNIX SDL_FILESYSTEM_ANDROID SDL_LOADSO_DLOPEN SDL_JOYSTICK_DISABLED SDL_DIALOG_DISABLED SDL_GPU_DISABLED SDL_RENDER_DISABLED SDL_HAPTIC_DISABLED SDL_HIDAPI_DISABLED SDL_SENSOR_DISABLED SDL_CAMERA_DISABLED")

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
		"deps/SDL3-3.2.28/src/gpu/*.c",
		"deps/SDL3-3.2.28/src/haptic/SDL_haptic.c",
		"deps/SDL3-3.2.28/src/hidapi/SDL_hidapi.c", "deps/SDL3-3.2.28/src/hidapi/android/hid.cpp",
		"deps/SDL3-3.2.28/src/io/*.c", "deps/SDL3-3.2.28/src/io/generic/*.c",
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

	build_script := fmt.tprintf(
		`#!/bin/sh
set -e
NDK=%q
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
CCPP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++ --target=aarch64-linux-android29 --sysroot=$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
ROOT=%q
OUT=%q
cd "$ROOT"
rm -f "$OUT"/obj/*.o
while read -r f; do
  case "$f" in *.cpp)
    $CCPP -x c++ -c -O2 -fPIC -I"$OUT" -I"$SDLDIR/include" -I"$SDLDIR/src" "$ROOT/$f" -o "$OUT/obj/$(echo "${f#deps/SDL3-3.2.28/}" | tr / _).o"
    continue ;;
  esac
  $CC -x c -c -O2 -fPIC -I"$OUT" -I"$SDLDIR/include" -I"$SDLDIR/src" "$ROOT/$f" -o "$OUT/obj/$(echo "${f#deps/SDL3-3.2.28/}" | tr / _).o"
done < "%s/sources.txt"
$CC -shared -Wl,-soname,libSDL3.so -o "$OUT/libSDL3.so" "$OUT"/obj/*.o -llog -landroid -lEGL -lGLESv3 -ldl -lm -lc++_static -lc++abi
`,
		ndk, root(), fmt.tprintf("%s/%s", root(), out_dir), out_dir,
	)
	_ = os.write_entire_file_from_string(fmt.tprintf("%s/build_sdl.sh", out_dir), build_script)
	if !sh(fmt.tprintf("SDLDIR=%q sh %s/build_sdl.sh", sdl_dir(), out_dir)) {
		fail("SDL3 android build failed")
	}

	// sokol headers (GLES3)
	sokol_objects(fmt.tprintf("%s/%s", root(), out_dir), "SOKOL_GLES3",
		fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -I%s/include", ndk, ndk, root()))

	// odin object
	if !sh(fmt.tprintf(
		"ODIN_ANDROID_NDK=%q ANDROID_NDK=%q odin build app -collection:libs=vendors -define:SMOKE_FRAMES=%d -define:SAMPLE_ID=%d -o:speed -target:linux_arm64 -subtarget:android -minimum-os-version:29 -build-mode:obj -no-entry-point -out:%s/odin-app.o",
		ndk, ndk, smoke, sample_id, out_dir,
	)) {
		fail("odin android object build failed")
	}

	// rename + link libmain.so
	llvm_objcopy := fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy", ndk)
	sh(fmt.tprintf("%s --redefine-sym sdl_main_provider=SDL_main %s/odin-app.o", llvm_objcopy, out_dir))
	link := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++ --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -shared -Wl,-soname,libmain.so -o %s/libmain.so %s/odin-app.o %s/obj/sokol_*.o -L%s -lSDL3 -lEGL -lGLESv3 -llog -landroid -ldl -lm -lc++_static -lc++abi",
		ndk, ndk, out_dir, out_dir, out_dir, out_dir,
	)
	if !sh(link) {
		fail("libmain.so link failed")
	}
	sh(fmt.tprintf("cp %s/libSDL3.so %s/libmain.so android/app/src/main/jniLibs/arm64-v8a/", out_dir, out_dir))

	if !sh("(cd android && ./gradlew --no-daemon :app:assembleDebug)") {
		fail("gradle assembleDebug failed")
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

// ------------------------------------------------------------ ios

build_ios :: proc(sample_id, smoke: i32) {
	when ODIN_OS != .Darwin {
		fail("ios builds require macOS")
	}
	// generated ObjC trampoline: SDL callbacks forwarded to the Odin app
	entry_m := `#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL_main.h>

extern SDL_AppResult odin_app_Init(void **, int, char **);
extern SDL_AppResult odin_app_Iterate(void *);
extern SDL_AppResult odin_app_Event(void *, SDL_Event *);
extern void odin_app_Quit(void *, SDL_AppResult);
SDL_AppResult SDL_AppInit(void **s, int n, char **v) { return odin_app_Init(s, n, v); }
SDL_AppResult SDL_AppIterate(void *s) { return odin_app_Iterate(s); }
SDL_AppResult SDL_AppEvent(void *s, SDL_Event *e) { return odin_app_Event(s, e); }
void SDL_AppQuit(void *s, SDL_AppResult r) { odin_app_Quit(s, r); }
`
	sh("mkdir -p build/ios")
	_ = os.write_entire_file_from_string("build/ios/entry.m", entry_m)
	_ = os.write_entire_file_from_string("build/ios/project.yml", ios_project_yml())
	if !sh("xcodegen generate --spec build/ios/project.yml --project build/ios") {
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

ios_project_yml :: proc() -> string {
	return `name: OdinSokol
options:
  minimumXcodeGenVersion: 2.44.1
  deploymentTarget:
    iOS: "17.4"
projectReferences:
  SDL:
    path: ../../deps/SDL3-3.2.28/Xcode/SDL/SDL.xcodeproj
targets:
  odin-sokol:
    type: application
    platform: iOS
    sources:
      - entry.m
    settings:
      base:
        CLANG_ENABLE_OBJC_ARC: YES
        PRODUCT_BUNDLE_IDENTIFIER: dev.alfayez.odinsokol
        INFOPLIST_FILE: "$(SRCROOT)/../../ios/Info.plist"
        TARGETED_DEVICE_FAMILY: "1,2"
        ENABLE_USER_SCRIPT_SANDBOXING: NO
        ENABLE_DEBUG_DYLIB: NO
        HEADER_SEARCH_PATHS: "$(SRCROOT)/../../deps/SDL3-3.2.28/include"
        OTHER_LDFLAGS: '$(inherited) -lc++ "$(DERIVED_FILE_DIR)/odin-app.o" "$(DERIVED_FILE_DIR)/sokol_gfx.o" "$(DERIVED_FILE_DIR)/sokol_gl.o" "$(DERIVED_FILE_DIR)/sokol_debugtext.o" "$(DERIVED_FILE_DIR)/sokol_shape.o"'
    dependencies:
      - target: SDL/SDL3
        embed: true
        codeSign: true
      - sdk: OpenGLES.framework
      - sdk: Foundation.framework
      - sdk: QuartzCore.framework
      - sdk: CoreGraphics.framework
      - sdk: UIKit.framework
    preBuildScripts:
      - name: Compile Odin app + sokol headers
        script: |
          set -e
          root="$SRCROOT/../.."
          out="$DERIVED_FILE_DIR"
          odin_bin=$(command -v odin || echo /opt/homebrew/bin/odin)
          case $PLATFORM_NAME in iphoneos) plat=iphone;; iphonesimulator) plat=iphonesimulator;; *) echo "unsupported platform" >&2; exit 1;; esac
          objs=()
          for arch in $ARCHS; do
            "$odin_bin" build "$root/app" -collection:libs="$root/vendors" \
              -define:SMOKE_FRAMES="${SMOKE_FRAMES:-0}" -define:SAMPLE_ID="${SAMPLE_ID:-0}" \
              -o:speed -target:darwin_arm64 -subtarget:$plat -minimum-os-version:17.4 \
              -build-mode:obj -no-entry-point -out:"$out/odin-$plat-$arch.o"
            objs+=("$out/odin-$plat-$arch.o")
          done
          if [ ${#objs[@]} -gt 1 ]; then
            xcrun lipo -create "${objs[@]}" -output "$out/odin-app.o"
          else
            cp "${objs[0]}" "$out/odin-app.o"
          fi
          for unit in gfx gl debugtext shape; do
            case $unit in
              gfx)       header=sokol_gfx.h;       cflags="-DSOKOL_IMPL -include sokol_log.h";;
              gl)        header=sokol_gl.h;        cflags="-DSOKOL_GL_IMPL -include sokol_gfx.h";;
              debugtext) header=sokol_debugtext.h; cflags="-DSOKOL_DEBUGTEXT_IMPL -include sokol_gfx.h";;
              shape)     header=sokol_shape.h;     cflags="-DSOKOL_SHAPE_IMPL -include sokol_gfx.h";;
            esac
            for arch in $ARCHS; do
              xcrun -sdk "$SDKROOT" clang -x c -c -arch "$arch" -O2 -DSOKOL_NO_ENTRY -DSOKOL_GLES3 $cflags \
                -I"$root/vendors/sokol" "$root/vendors/sokol/$header" -o "$out/sokol_$unit-$arch.o"
            done
            if [ ${#ARCHS[@]} -gt 1 ]; then
              xcrun lipo -create "$out"/sokol_$unit-*.o -output "$out/sokol_$unit.o"
            else
              cp "$out/sokol_$unit-${ARCHS[0]}.o" "$out/sokol_$unit.o"
            fi
          done
        basedOnDependencyAnalysis: false
        showEnvVars: false
        outputFiles:
          - $(DERIVED_FILE_DIR)/odin-app.o
schemes:
  odin-sokol:
    build:
      targets:
        odin-sokol: all
`
}
