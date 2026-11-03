package androidgen

import "core:strings"

resolve_target_templates :: proc(project: Map) -> Map {
	templates, has_templates := m_get(project, "targetTemplates")
	if !has_templates do return project
	tm, ok := templates.(Map)
	if !ok do return project
	targets_v, has_targets := m_get(project, "targets")
	if !has_targets do return project
	targets, ok2 := targets_v.(Map)
	if !ok2 do return project

	resolved := m_empty()
	for key in targets.keys {
		target_v := targets.values[key]
		target, ok3 := target_v.(Map)
		if !ok3 {
			m_set(&resolved, key, target_v)
			continue
		}
		names := make([dynamic]string)
		seen := make(map[string]bool)
		collect_template_names(target, tm, &names, &seen)
		merged := m_empty()
		for name in names {
			if tv, has := m_get(tm, name); has {
				if tvm, ok4 := tv.(Map); ok4 do merged = m_merge(merged, tvm)
			}
		}
		merged = m_merge(merged, target)
		vars := make(map[string]string)
		vars["target_name"] = key
		if attrs, has := m_get(target, "templateAttributes"); has {
			if am, ok4 := attrs.(Map); ok4 {
				for k in am.keys do vars[k] = value_string(am.values[k])
			}
		}
		expanded := expand_vars(merged, vars)
		m_set(&resolved, key, expanded)
	}
	out := m_clone(project)
	m_set(&out, "targets", resolved)
	return out
}

collect_template_names :: proc(target: Map, templates: Map, names: ^[dynamic]string, seen: ^map[string]bool) {
	tv, has := m_get(target, "templates")
	if !has do return
	list := value_array_strings(tv)
	for name in list {
		if seen[name] do continue
		seen[name] = true
		if tmpl_v, has2 := m_get(templates, name); has2 {
			if tmpl, ok := tmpl_v.(Map); ok {
				collect_template_names(tmpl, templates, names, seen)
			}
			append(names, name)
		}
	}
}

expand_vars :: proc(v: Value, vars: map[string]string) -> Value {
	#partial switch x in v {
	case string:
		out := x
		for k, val in vars {
			needle := strings.concatenate([]string{"${", k, "}"})
			out, _ = strings.replace_all(out, needle, val)
		}
		return out
	case []Value:
		na := make([]Value, len(x))
		for item, i in x do na[i] = expand_vars(item, vars)
		return na
	case Map:
		out := m_empty()
		for k in x.keys {
			new_key := k
			for vk, val in vars {
				needle := strings.concatenate([]string{"${", vk, "}"})
				new_key, _ = strings.replace_all(new_key, needle, val)
			}
			m_set(&out, new_key, expand_vars(x.values[k], vars))
		}
		return out
	case:
		return v
	}
}
