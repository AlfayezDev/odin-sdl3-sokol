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
	case "shaders":
		run_shaders()
	case:
		fmt.eprintln("unknown target:", target)
		fmt.eprintln("usage: odin run . -- [desktop|android|ios|shaders]")
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
			if sp := find(name, " "); sp >= 0 do name = name[:sp]
			if defines[name] {
				fmt.sbprintf(&b, "#define %s 1\n", name)
			} else {
				fmt.sbprintf(&b, "/* #undef %s */\n", name)
			}
		} else if strings.has_prefix(s, "#cmakedefine01 ") {
			name := strings.trim_space(s[len("#cmakedefine01"):])
			if sp := find(name, " "); sp >= 0 do name = name[:sp]
			v := i32(0)
			if defines[name] do v = 1
			fmt.sbprintf(&b, "#define %s %d\n", name, v)
		} else {
			fmt.sbprintf(&b, "%s\n", line)
		}
	}
	txt := strings.to_string(b)
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
	sum_cmd := "sha256sum deps/SDL3.tar.gz"
	if !sh("command -v sha256sum >/dev/null") {
		sum_cmd = "shasum -a 256 deps/SDL3.tar.gz"
	}
	if !sh(fmt.tprintf("%s | grep -q ^1330671214d146f8aeb1ed399fc3e081873cdb38b5189d1f8bb6ab15bbc04211", sum_cmd)) {
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
		header := fmt.tprintf("sokol_%s.h", unit)
		flags := ""
		if unit == "gfx" {
			flags = "-DSOKOL_IMPL -include sokol_log.h"
		} else {
			flags = fmt.tprintf("-DSOKOL_%s_IMPL -include sokol_gfx.h", strings.to_upper(unit))
		}
		cmd := fmt.tprintf(
			"%s -x c -c -O2 -DSOKOL_NO_ENTRY -D%s %s -I%s -I vendors/sokol vendors/sokol/%s -o %s/obj/sokol_%s.o",
			cc, backend, flags, out_dir, header, out_dir, unit,
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

// ------------------------------------------------------------ shaders

slice_contains :: proc(s: []string, v: string) -> bool {
	for x in s {
		if x == v {
			return true
		}
	}
	return false
}

is_ident_byte :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

ident_needs_prefix :: proc(word: string) -> bool {
	if word == "sg" {
		return false
	}
	if (strings.has_prefix(word, "vs_") || strings.has_prefix(word, "fs_")) && strings.contains(word, "_source_") {
		return true
	}
	if strings.has_suffix(word, "_shader_desc") {
		return true
	}
	if strings.has_suffix(word, "_Params") && word[0] >= 'A' && word[0] <= 'Z' {
		return true
	}
	if strings.has_prefix(word, "ATTR_") || strings.has_prefix(word, "UB_") || strings.has_prefix(word, "VIEW_") || strings.has_prefix(word, "SMP_") {
		return true
	}
	return false
}

prefix_idents :: proc(text, prefix: string) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	i := 0
	for i < len(text) {
		if is_ident_byte(text[i]) {
			j := i
			for j < len(text) && is_ident_byte(text[j]) {
				j += 1
			}
			word := text[i:j]
			if ident_needs_prefix(word) {
				strings.write_string(&b, prefix)
				strings.write_rune(&b, '_')
			}
			strings.write_string(&b, word)
			i = j
		} else {
			strings.write_byte(&b, text[i])
			i += 1
		}
	}
	return strings.to_string(b)
}

ident_words :: proc(text: string) -> [dynamic]string {
	words: [dynamic]string
	i := 0
	for i < len(text) {
		if is_ident_byte(text[i]) {
			j := i
			for j < len(text) && is_ident_byte(text[j]) {
				j += 1
			}
			append(&words, text[i:j])
			i = j
		} else {
			i += 1
		}
	}
	return words
}

shdc_odin :: proc(shdc, src, slang: string) -> string {
	raw := fmt.tprintf("build/shaders_tmp/%s.%s.raw", strings.trim_suffix(strings.trim_prefix(src, "shaders/samples/"), ".glsl"), slang)
	if !sh(fmt.tprintf("%s -i %s -o %s -l %s --format sokol_odin", shdc, src, raw, slang)) {
		fail(fmt.tprintf("sokol-shdc failed for %s (%s)", src, slang))
	}
	return file_text(raw)
}

run_shaders :: proc() {
	shdc := "vendors/tools/sokol-shdc"
	entries, derr := os.read_directory_by_path("shaders/samples", -1, context.allocator)
	if derr != nil {
		fail("cannot list shaders/samples")
	}
	sh("mkdir -p build/shaders_tmp vendors/shaders")
	for e in entries {
		if !strings.has_suffix(e.name, ".glsl") {
			continue
		}
		name := strings.trim_suffix(e.name, ".glsl")
		src := fmt.tprintf("shaders/samples/%s", e.name)
		gl4 := shdc_odin(shdc, src, "glsl410")
		gles := shdc_odin(shdc, src, "glsl300es")
		gl4 = prefix_idents(gl4, fmt.tprintf("%s_gl4", name))
		gles = prefix_idents(gles, name)
		gl4, _ = strings.replace_all(gl4, ".array_count = 0", ".array_count = 1")
		gles, _ = strings.replace_all(gles, ".array_count = 0", ".array_count = 1")

		// collect the prefixed desc procs, then suffix the gles3 originals
		name_pfx := fmt.tprintf("%s_", name)
		progs: [dynamic]string
		for w in ident_words(gles) {
			if strings.has_suffix(w, "_shader_desc") && strings.has_prefix(w, name_pfx) {
				prog := strings.trim_suffix(strings.trim_prefix(w, name_pfx), "_shader_desc")
				if !strings.has_prefix(prog, "gl4_") && !slice_contains(progs[:], prog) {
					append(&progs, prog)
				}
			}
		}
		fmt.println("DEBUG progs:", len(progs), progs)
		db: strings.Builder
		strings.builder_init(&db)
		for prog in progs {
			gles, _ = strings.replace_all(
				gles,
				fmt.tprintf("%s_%s_shader_desc :: proc", name, prog),
				fmt.tprintf("%s_%s_shader_desc_gles3 :: proc", name, prog),
			)
			fmt.sbprintf(&db, "%s_%s_shader_desc :: proc \"c\" (backend: sg.Backend) -> sg.Shader_Desc {{\n", name, prog)
			fmt.sbprintf(&db, "\t#partial switch backend {{\n")
			fmt.sbprintf(&db, "\tcase .GLES3:\n\t\treturn %s_%s_shader_desc_gles3(backend)\n", name, prog)
			fmt.sbprintf(&db, "\tcase .GLCORE:\n\t\treturn %s_gl4_%s_shader_desc(backend)\n", name, prog)
			fmt.sbprintf(&db, "\t}}\n\treturn {{}}\n}\n")
		}

		out := fmt.tprintf(
			"// Generated by build.odin (sokol-shdc). Do not edit.\npackage shaders\n\nimport sg \"libs:sg\"\n\n%s\n%s\n%s",
			gl4, gles, strings.to_string(db),
		)
		werr := os.write_entire_file_from_string(fmt.tprintf("vendors/shaders/%s.odin", name), out)
		if werr != nil {
			fail(fmt.tprintf("failed to write vendors/shaders/%s.odin: %v", name, werr))
		}
		fmt.println("wrote vendors/shaders/", name, ".odin")
	}
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


// ------------------------------------------------------------ android

build_android :: proc(sample_id, smoke: i32) {
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
		"ODIN_ANDROID_NDK=%q ANDROID_NDK=%q odin build app -collection:libs=vendors -define:SMOKE_FRAMES=%d -define:SAMPLE_ID=%d -o:speed -target:linux_arm64 -subtarget:android -minimum-os-version:29 -build-mode:obj -no-entry-point -out:%s/odin-app.o",
		ndk, ndk, smoke, sample_id, out_dir,
	)) {
		fail("odin android object build failed")
	}

	// rename + link libmain.so
	llvm_objcopy := fmt.tprintf("%s/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy", ndk)
	sh(fmt.tprintf("%s --redefine-sym sdl_main_provider=SDL_main %s/odin-app.o", llvm_objcopy, out_dir))
	link := fmt.tprintf(
		"%s/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --target=aarch64-linux-android29 --sysroot=%s/toolchains/llvm/prebuilt/linux-x86_64/sysroot -shared -Wl,-soname,libmain.so -o %s/libmain.so %s/odin-app.o %s/obj/sokol_*.o -L%s -lSDL3 -lEGL -lGLESv3 -llog -landroid -ldl -lm",
		ndk, ndk, out_dir, out_dir, out_dir, out_dir,
	)
	if !sh(link) {
		fail("libmain.so link failed")
	}
	sh(fmt.tprintf("cp %s/libSDL3.so %s/libmain.so build/android/jni/arm64-v8a/", out_dir, out_dir))

	// generate the gradle project from binding/android (androidgen)
	if !sh("test -x build/tools/androidgen") {
		if !sh("odin build tools/androidgen/src -o:speed -out:build/tools/androidgen") {
			fail("androidgen build failed")
		}
	}
	if !sh("build/tools/androidgen generate --spec binding/android/project.yaml --out android --templates tools/androidgen") {
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

// ------------------------------------------------------------ ios

build_ios :: proc(sample_id, smoke: i32) {
	when ODIN_OS != .Darwin {
		fail("ios builds require macOS")
	}
	// generated ObjC trampoline: SDL callbacks forwarded to the Odin app
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

