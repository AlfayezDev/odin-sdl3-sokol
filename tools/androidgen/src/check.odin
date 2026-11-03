package androidgen

import "core:fmt"
import "core:strings"

Target_Common :: struct {
	name:         string,
	type:         string,
	platform:     string,
	app_id:       string,
	version_name: string,
	version_code: string,
}

Spec_Common :: struct {
	name:         string,
	configs:      []string,
	target_names: []string,
	targets:      map[string]Target_Common,
}

extract_common :: proc(v: Value) -> Spec_Common {
	out := Spec_Common{targets = make(map[string]Target_Common)}
	m, ok := v.(Map)
	if !ok do return out
	m = resolve_target_templates(m)
	out.name = m_get_string(m, "name")
	out.configs = default_config_names(m_get_or(m, "configs", nil))
	if targets, has := m_get(m, "targets"); has {
		if tm, ok2 := targets.(Map); ok2 {
			names := make([dynamic]string)
			for key in tm.keys {
				t, ok3 := tm.values[key].(Map)
				if !ok3 do continue
				name := m_get_string_or(t, "name", key)
				append(&names, name)
				out.targets[name] = target_common(m, t, name)
			}
			out.target_names = names[:]
		}
	}
	return out
}

default_config_names :: proc(v: Value) -> []string {
	if m, ok := v.(Map); ok && len(m.keys) > 0 {
		out := make([]string, len(m.keys))
		for k, i in m.keys do out[i] = k
		return out
	}
	out := make([]string, 2)
	out[0] = "Debug"
	out[1] = "Release"
	return out
}

target_common :: proc(project: Map, target: Map, fallback_name: string) -> Target_Common {
	groups := Map{}
	if gv, has := m_get(project, "settingGroups"); has {
		if gm, ok := gv.(Map); ok do groups = gm
	}
	settings := m_empty()
	if pv, has := m_get(project, "settings"); has {
		settings = flatten_settings(groups, pv)
	}
	if tv, has := m_get(target, "settings"); has {
		settings = m_merge(settings, flatten_settings(groups, tv))
	}
	app_id := setting_first(settings, []string{"PRODUCT_BUNDLE_IDENTIFIER", "applicationId"})
	version_name := setting_first(settings, []string{"MARKETING_VERSION", "versionName"})
	version_code := setting_first(settings, []string{"CURRENT_PROJECT_VERSION", "versionCode"})
	if av, has := m_get(target, "android"); has {
		if am, ok := av.(Map); ok {
			if app_id == "" do app_id = m_get_string(am, "applicationId")
			if version_name == "" do version_name = m_get_string(am, "versionName")
			if version_code == "" {
				if vc, has2 := m_get(am, "versionCode"); has2 do version_code = value_string(vc)
			}
		}
	}
	return Target_Common{
		name = m_get_string_or(target, "name", fallback_name),
		type = m_get_string(target, "type"),
		platform = m_get_string(target, "platform"),
		app_id = app_id,
		version_name = version_name,
		version_code = version_code,
	}
}

flatten_settings :: proc(groups: Map, v: Value) -> Map {
	return flatten_settings_depth(groups, v, 0)
}

flatten_settings_depth :: proc(groups: Map, v: Value, depth: int) -> Map {
	if depth > 16 do return m_empty()
	settings := parse_settings(v)
	out := m_empty()
	for group in settings.groups {
		if gv, has := m_get(groups, group); has {
			out = m_merge(out, flatten_settings_depth(groups, gv, depth + 1))
		}
	}
	out = m_merge(out, settings.base)
	return out
}

check_manifest :: proc(manifest_path: string) -> string {
	manifest, err := load_manifest(manifest_path)
	if err != "" do return err
	commons := make([dynamic]Spec_Common)
	names := make([dynamic]string)
	for p in manifest.platforms {
		if !p.enabled do continue
		spec := p.spec
		if !strings.has_suffix(spec, ".json") && !strings.has_suffix(spec, ".yaml") && !strings.has_suffix(spec, ".yml") {
			spec = strings.concatenate([]string{spec, ".yaml"})
		}
		if !is_abs_path(spec) do spec = join_path(manifest.root, spec)
		root := p.project_root
		if root == "" do root = manifest.root
		if !is_abs_path(root) do root = join_path(manifest.root, root)
		loaded, load_err := load_spec(spec, root)
		if load_err != "" do return load_err
		append(&commons, extract_common(loaded.value))
		append(&names, p.name)
	}
	if len(commons) < 2 do return "coherence check needs at least two enabled platforms"

	errors := make([dynamic]string)
	base := commons[0]
	for i in 1 ..< len(commons) {
		other := commons[i]
		if base.name != other.name {
			append(&errors, fmt.tprintf("name: %s=%q, %s=%q", names[0], base.name, names[i], other.name))
		}
		if !same_string_set(base.configs, other.configs) {
			append(&errors, fmt.tprintf("configs: %s=%v, %s=%v", names[0], base.configs, names[i], other.configs))
		}
		for target_name in base.target_names {
			bt, has_b := base.targets[target_name]
			ot, has_o := other.targets[target_name]
			if !has_b || !has_o {
				append(&errors, fmt.tprintf("target %s missing from one platform (%s)", target_name, names[i]))
				continue
			}
			if bt.type != ot.type {
				append(&errors, fmt.tprintf("target %s type: %s=%q, %s=%q", target_name, names[0], bt.type, names[i], ot.type))
			}
			if bt.app_id != "" && ot.app_id != "" && bt.app_id != ot.app_id {
				append(&errors, fmt.tprintf("target %s app id: %s=%q, %s=%q", target_name, names[0], bt.app_id, names[i], ot.app_id))
			}
			if bt.version_name != "" && ot.version_name != "" && bt.version_name != ot.version_name {
				append(&errors, fmt.tprintf("target %s version: %s=%q, %s=%q", target_name, names[0], bt.version_name, names[i], ot.version_name))
			}
			if bt.version_code != "" && ot.version_code != "" && bt.version_code != ot.version_code {
				append(&errors, fmt.tprintf("target %s build: %s=%q, %s=%q", target_name, names[0], bt.version_code, names[i], ot.version_code))
			}
		}
		for target_name in other.target_names {
			if _, has := base.targets[target_name]; !has {
				append(&errors, fmt.tprintf("target %s exists only on %s", target_name, names[i]))
			}
		}
	}
	if len(errors) > 0 do return strings.join(errors[:], "\n")
	return ""
}

same_string_set :: proc(a, b: []string) -> bool {
	if len(a) != len(b) do return false
	for s in a {
		found := false
		for t in b {
			if s == t do found = true
		}
		if !found do return false
	}
	return true
}
