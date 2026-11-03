package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

fnv1a :: proc(s: string) -> u64 {
	h := u64(0xcbf29ce484222325)
	for c in s {
		h ~= u64(c)
		h *= u64(0x100000001b3)
	}
	return h
}

default_cache_path :: proc(spec_path: string) -> string {
	home, err := os.user_home_dir(context.allocator)
	if err != nil || home == "" {
		home = os.get_env("HOME", context.allocator)
	}
	if home == "" do home = "."
	hash := fnv1a(clean_path(spec_path))
	return join_path(join_path(join_path(home, ".androidgen"), "cache"), fmt.tprintf("%016x", hash))
}

collect_tracked_files :: proc(project: ^Project) -> []string {
	out := make([dynamic]string)
	for b in project.bindings {
		if os.is_file(b.source) do append(&out, b.source)
	}
	for t in project.targets {
		for source in t.sources {
			path := source.path
			if path == "" do continue
			if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
			path = clean_path(path)
			if os.is_dir(path) {
				files := make([dynamic]string)
				if walk_files(path, &files) == "" {
					for f in files do append(&out, f)
				}
			} else if os.is_file(path) {
				append(&out, path)
			}
		}
	}
	sort_strings(out[:])
	return out[:]
}

make_cache_string :: proc(project: ^Project, loaded: Spec_Load_Result) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	strings.write_string(&b, "# ANDROIDGEN VERSION\n")
	strings.write_string(&b, VERSION)
	strings.write_string(&b, "\n\n# SPEC\n")
	strings.write_string(&b, yaml_dump_value(loaded.value))
	strings.write_string(&b, "\n# FILES\n")
	files := collect_tracked_files(project)
	for f in files {
		strings.write_string(&b, f)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

cache_matches :: proc(project: ^Project, loaded: Spec_Load_Result, cache_path: string) -> bool {
	data, err := os.read_entire_file_from_path(cache_path, context.allocator)
	if err != nil do return false
	expected := make_cache_string(project, loaded)
	return string(data) == expected
}

write_cache :: proc(project: ^Project, loaded: Spec_Load_Result, cache_path: string) {
	parent := filepath.dir(cache_path)
	if parent != "" do os.mkdir_all(parent)
	_ = os.write_entire_file_from_string(cache_path, make_cache_string(project, loaded))
}

write_cache_for_spec :: proc(spec, project_root: string, no_env: bool, cache_path: string, quiet: bool) -> string {
	project, loaded, err := load_and_parse_project(spec, project_root, "", no_env)
	if err != "" do return err
	path := cache_path
	if path == "" do path = default_cache_path(loaded.path)
	write_cache(&project, loaded, path)
	if !quiet do fmt.println("androidgen: wrote cache to", path)
	return ""
}
