package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Legacy_Spec :: struct {
	values: map[string][dynamic]string,
}

is_legacy_file :: proc(path: string) -> bool {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return false
	return looks_like_legacy(string(data))
}

looks_like_legacy :: proc(text: string) -> bool {
	has_app_id := false
	has_root_name := false
	has_targets := false
	has_name := false
	for line in strings.split(text, "\n") {
		s := strings.trim_space(line)
		if len(s) == 0 || s[0] == '#' do continue
		if strings.has_prefix(s, "app_id:") do has_app_id = true
		if strings.has_prefix(s, "root_project_name:") do has_root_name = true
		if strings.has_prefix(s, "targets:") do has_targets = true
		if strings.has_prefix(s, "name:") do has_name = true
	}
	return (has_app_id || (has_root_name && !has_name)) && !has_targets
}

parse_legacy_values :: proc(text: string) -> Legacy_Spec {
	spec := Legacy_Spec{values = make(map[string][dynamic]string)}
	for line in strings.split(text, "\n") {
		s := strings.trim_space(line)
		if len(s) == 0 || s[0] == '#' do continue
		colon := -1
		for i in 0 ..< len(s) {
			if s[i] == ':' {
				colon = i
				break
			}
		}
		if colon <= 0 do continue
		key := strings.trim_space(s[:colon])
		value := strings.trim_space(s[colon + 1:])
		if hash := strings.index_byte(value, '#'); hash >= 0 {
			if hash == 0 || value[hash - 1] == ' ' || value[hash - 1] == '\t' {
				value = strings.trim_space(value[:hash])
			}
		}
		if _, has := spec.values[key]; !has {
			spec.values[key] = make([dynamic]string)
		}
		append(&spec.values[key], value)
	}
	return spec
}

legacy_first :: proc(spec: Legacy_Spec, key: string) -> string {
	if values, has := spec.values[key]; has && len(values) > 0 do return values[0]
	return ""
}

legacy_all :: proc(spec: Legacy_Spec, key: string) -> []string {
	if values, has := spec.values[key]; has do return values[:]
	return nil
}

load_legacy_project :: proc(path, project_root, output_override: string) -> (Project, Spec_Load_Result, string) {
	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil do return {}, {}, fmt.tprintf("cannot resolve spec: %s", path)
	data, read_err := os.read_entire_file_from_path(abs_path, context.allocator)
	if read_err != nil do return {}, {}, fmt.tprintf("cannot read spec: %s", abs_path)
	spec := parse_legacy_values(string(data))

	base_dir := project_root
	if base_dir == "" {
		base_dir = filepath.dir(abs_path)
	} else {
		bd, bd_err := filepath.abs(base_dir)
		if bd_err != nil do return {}, {}, fmt.tprintf("cannot resolve project root: %s", project_root)
		base_dir = bd
	}

	name := legacy_first(spec, "root_project_name")
	if name == "" do name = "app"

	opts_android := m_empty()
	set_str(&opts_android, "agpVersion", legacy_first(spec, "agp_version"))
	set_str(&opts_android, "gradleVersion", legacy_first(spec, "gradle_version"))
	set_str(&opts_android, "gradleSha256", legacy_first(spec, "gradle_sha256"))
	set_str(&opts_android, "kotlinVersion", legacy_first(spec, "kotlin_version"))
	set_str(&opts_android, "buildToolsVersion", legacy_first(spec, "build_tools_version"))
	set_str(&opts_android, "ndkVersion", legacy_first(spec, "ndk_version"))
	if v := legacy_first(spec, "compile_sdk"); v != "" do m_set(&opts_android, "compileSdk", parse_i64_value(v))

	opts := m_empty()
	m_set(&opts, "android", opts_android)
	if v := legacy_first(spec, "min_sdk"); v != "" {
		dt := m_empty()
		m_set(&dt, "Android", parse_i64_value(v))
		m_set(&opts, "deploymentTarget", dt)
	}

	settings := m_empty()
	set_str(&settings, "applicationId", legacy_first(spec, "app_id"))
	set_str(&settings, "namespace", legacy_first(spec, "namespace"))
	if v := legacy_first(spec, "version_code"); v != "" do m_set(&settings, "versionCode", parse_i64_value(v))
	set_str(&settings, "versionName", legacy_first(spec, "version_name"))
	settings_wrapper := m_empty()
	m_set(&settings_wrapper, "base", settings)

	android := m_empty()
	abis := legacy_all(spec, "abi")
	if len(abis) > 0 {
		abi_values := make([]Value, len(abis))
		for a, i in abis do abi_values[i] = a
		m_set(&android, "abiFilters", abi_values)
	}
	if v := legacy_first(spec, "target_sdk"); v != "" do m_set(&android, "targetSdk", parse_i64_value(v))

	sources := make([dynamic]Value)
	add_legacy_source(&sources, legacy_first(spec, "manifest"), "manifest")
	add_legacy_source(&sources, legacy_first(spec, "res"), "res")
	for java in legacy_all(spec, "java") {
		add_legacy_source(&sources, java, "java")
	}
	add_legacy_source(&sources, legacy_first(spec, "jni_libs"), "jniLibs")
	add_legacy_source(&sources, legacy_first(spec, "proguard"), "proguard")

	target := m_empty()
	m_set(&target, "type", "application")
	m_set(&target, "platform", "Android")
	m_set(&target, "settings", settings_wrapper)
	m_set(&target, "sources", sources[:])
	if len(android.keys) > 0 do m_set(&target, "android", android)

	targets := m_empty()
	m_set(&targets, "app", target)

	configs := m_empty()
	m_set(&configs, "Debug", "debug")
	m_set(&configs, "Release", "release")

	root := m_empty()
	m_set(&root, "name", name)
	m_set(&root, "options", opts)
	m_set(&root, "configs", configs)
	m_set(&root, "targets", targets)

	loaded := Spec_Load_Result{value = root, path = abs_path, base_dir = base_dir, disable_env = true}
	project, err := parse_project(loaded, output_override)
	if err != "" do return {}, loaded, err
	return project, loaded, ""
}

set_str :: proc(m: ^Map, key, value: string) {
	if value != "" do m_set(m, key, value)
}

parse_i64_value :: proc(s: string) -> i64 {
	if n, ok := parse_i64(s); ok do return n
	return 0
}

parse_i64 :: proc(s: string) -> (i64, bool) {
	// small local helper to avoid importing strconv in this file
	n: i64 = 0
	if s == "" do return 0, false
	for c in s {
		if c < '0' || c > '9' do return 0, false
		n = n * 10 + i64(c - '0')
	}
	return n, true
}

add_legacy_source :: proc(sources: ^[dynamic]Value, path, phase: string) {
	if path == "" do return
	m := m_empty()
	m_set(&m, "path", path)
	m_set(&m, "buildPhase", phase)
	append(sources, m)
}
