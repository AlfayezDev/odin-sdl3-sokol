package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Platform_Entry :: struct {
	name:         string,
	generator:    string,
	spec:         string,
	project:      string,
	project_root: string,
	command:      string,
	args:         []string,
	enabled:      bool,
}

Manifest :: struct {
	name:             string,
	root:             string,
	path:             string,
	default_platform: string,
	platforms:        []Platform_Entry,
}

looks_like_manifest :: proc(path: string) -> bool {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return false
	parsed, perr := yaml_parse(string(data))
	if perr != "" do return false
	m, ok := parsed.(Map)
	if !ok do return false
	return m_has(m, "platforms")
}

load_manifest :: proc(path: string) -> (Manifest, string) {
	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil do return {}, fmt.tprintf("cannot resolve manifest: %s", path)
	data, read_err := os.read_entire_file_from_path(abs_path, context.allocator)
	if read_err != nil do return {}, fmt.tprintf("cannot read manifest: %s", abs_path)
	parsed, parse_err := yaml_parse(string(data))
	if parse_err != "" do return {}, fmt.tprintf("%s: %s", abs_path, parse_err)
	parsed = expand_env(parsed)
	m, ok := parsed.(Map)
	if !ok do return {}, fmt.tprintf("%s: manifest root must be a mapping", abs_path)

	manifest := Manifest {
		name             = m_get_string_or(m, "name", "project"),
		root             = filepath.dir(abs_path),
		path             = abs_path,
		default_platform = m_get_string_or(m, "defaultPlatform", "android"),
	}
	platforms_v, has := m_get(m, "platforms")
	if !has do return {}, fmt.tprintf("%s: manifest has no platforms", abs_path)
	pm, ok2 := platforms_v.(Map)
	if !ok2 do return {}, fmt.tprintf("%s: platforms must be a mapping", abs_path)
	out := make([dynamic]Platform_Entry)
	for name in pm.keys {
		entry_v := pm.values[name]
		em, ok3 := entry_v.(Map)
		if !ok3 {
			return {}, fmt.tprintf("%s: platform %s must be a mapping", abs_path, name)
		}
		generator := m_get_string(em, "generator")
		if generator == "" {
			if strings.equal_fold(name, "android") do generator = "androidgen"
			else if strings.equal_fold(name, "ios") do generator = "xcodegen"
		}
		spec := m_get_string_or(em, "spec", strings.concatenate([]string{name, ".yaml"}))
		project := m_get_string_or(em, "project", strings.concatenate([]string{"build/", name}))
		append(&out, Platform_Entry{
			name = name,
			generator = generator,
			spec = spec,
			project = project,
			project_root = m_get_string(em, "projectRoot"),
			command = m_get_string(em, "command"),
			args = value_array_strings(m_get_or(em, "args", nil)),
			enabled = value_bool(m_get_or(em, "enabled", true), true),
		})
	}
	if len(out) == 0 do return {}, fmt.tprintf("%s: manifest has no platforms", abs_path)
	manifest.platforms = out[:]
	return manifest, ""
}
