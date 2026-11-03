package odin_sokol_build

// SDL configuration and sokol object compilation.

import "core:fmt"
import "core:os"
import "core:strings"

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
	sh(fmt.tprintf("mkdir -p %s/obj", out_dir))
	cmd := fmt.tprintf(
		"%s -x c -c -O2 -DSOKOL_NO_ENTRY -D%s -DSOKOL_IMPL -include sokol_log.h -I%s -I vendors/sokol vendors/sokol/sokol_gfx.h -o %s/obj/sokol_gfx.o",
		cc, backend, out_dir, out_dir,
	)
	if !sh(cmd) {
		fail("sokol_gfx header compile failed")
	}
}
