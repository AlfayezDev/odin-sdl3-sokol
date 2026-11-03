package androidgen

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Spec_Load_Result :: struct {
	value:       Map,
	path:        string,
	base_dir:    string,
	disable_env: bool,
}

Spec_Load_Context :: struct {
	root_base:   string,
	disable_env: bool,
	seen:        map[string]bool,
	depth:       int,
}

load_spec :: proc(path: string, project_root: string) -> (Spec_Load_Result, string) {
	return load_spec_opts(path, project_root, false)
}

load_spec_opts :: proc(path: string, project_root: string, disable_env: bool) -> (Spec_Load_Result, string) {
	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil do return {}, fmt.tprintf("cannot resolve spec path: %s", path)
	root_base := project_root
	if root_base == "" {
		root_base = filepath.dir(abs_path)
	} else {
		rb, rb_err := filepath.abs(root_base)
		if rb_err != nil do return {}, fmt.tprintf("cannot resolve project root: %s", project_root)
		root_base = rb
	}
	ctx := Spec_Load_Context {
		root_base   = root_base,
		disable_env = disable_env,
		seen        = make(map[string]bool),
	}
	ctx.seen[abs_path] = true
	value, err := load_spec_recursive(&ctx, abs_path, root_base)
	if err != "" do return {}, err
	return Spec_Load_Result{value = value, path = abs_path, base_dir = root_base, disable_env = disable_env}, ""
}

load_spec_recursive :: proc(ctx: ^Spec_Load_Context, path, base_dir: string) -> (Map, string) {
	ctx.depth += 1
	defer ctx.depth -= 1
	if ctx.depth > 64 do return {}, "include depth exceeded (cycle?)"

	data, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil do return {}, fmt.tprintf("cannot read spec: %s", path)
	parsed, parse_err := parse_spec_text(string(data), path)
	if parse_err != "" do return {}, fmt.tprintf("%s: %s", path, parse_err)
	if ctx.disable_env == false {
		parsed = expand_env(parsed)
	}
	m, ok := parsed.(Map)
	if !ok do return {}, fmt.tprintf("%s: spec root must be a mapping", path)

	// Include paths are resolved relative to the file that contains them.
	file_dir := filepath.dir(path)
	merged := m_empty()
	if inc, has := m_get(m, "include"); has {
		includes := parse_includes(inc)
		for include in includes {
			if !include.enable do continue
			inc_path := include.path
			if !filepath.is_abs(inc_path) {
				inc_path = join_path(file_dir, inc_path)
			}
			abs_inc, abs_err := filepath.abs(inc_path)
			if abs_err != nil do return {}, fmt.tprintf("cannot resolve include: %s", include.path)
			if !os.is_file(abs_inc) do return {}, fmt.tprintf("included spec does not exist: %s", abs_inc)
			if ctx.seen[abs_inc] do continue
			ctx.seen[abs_inc] = true
			inc_base := base_dir
			if include.relative_paths {
				inc_base = filepath.dir(abs_inc)
			}
			inc_value, inc_err := load_spec_recursive(ctx, abs_inc, inc_base)
			if inc_err != "" do return {}, inc_err
			merged = m_merge(merged, inc_value)
		}
	}

	// Paths in this file resolve against its base directory, not necessarily
	// the directory containing the file (project-root can override).
	prefix := ""
	rel, rel_err := filepath.rel(ctx.root_base, base_dir)
	if rel_err == nil && rel != "." do prefix = rel
	current_v := rewrite_paths(m, prefix)
	current, current_ok := current_v.(Map)
	if !current_ok do return {}, fmt.tprintf("%s: spec root must be a mapping", path)
	return m_merge(merged, current), ""
}

parse_spec_text :: proc(text, path: string) -> (Value, string) {
	if strings.has_suffix(strings.to_lower(path), ".json") {
		return parse_json_spec(text)
	}
	return yaml_parse(text)
}

parse_json_spec :: proc(text: string) -> (Value, string) {
	value, err := json.parse(text, json.Specification.JSON, false, context.allocator)
	if err != nil do return nil, fmt.tprintf("invalid JSON: %v", err)
	return json_to_value(value), ""
}

json_to_value :: proc(v: json.Value) -> Value {
	switch x in v {
	case json.Null:
		return nil
	case json.Boolean:
		return bool(x)
	case json.Integer:
		return i64(x)
	case json.Float:
		return f64(x)
	case json.String:
		return strings.clone(string(x))
	case json.Array:
		out := make([dynamic]Value, 0, len(x))
		for item in x do append(&out, json_to_value(item))
		return out[:]
	case json.Object:
		m := m_empty()
		keys := make([dynamic]string, 0, len(x))
		for key in x do append(&keys, key)
		sort_strings(keys[:])
		for key in keys do m_set(&m, strings.clone(key), json_to_value(x[key]))
		return m
	}
	return nil
}

Include :: struct {
	path:           string,
	relative_paths: bool,
	enable:         bool,
}

parse_includes :: proc(v: Value) -> []Include {
	out := make([dynamic]Include)
	if s, ok := v.(string); ok {
		append(&out, Include{path = s, relative_paths = true, enable = true})
		return out[:]
	}
	if a, ok := v.([]Value); ok {
		for item in a {
			if s, ok2 := item.(string); ok2 {
				append(&out, Include{path = s, relative_paths = true, enable = true})
			} else if m, ok2 := item.(Map); ok2 {
				path := m_get_string(m, "path")
				if path == "" do continue
				append(&out, Include{
					path = path,
					relative_paths = value_bool(m_get_or(m, "relativePaths", true), true),
					enable = include_enabled(m_get_or(m, "enable", true)),
				})
			}
		}
		return out[:]
	}
	if m, ok := v.(Map); ok {
		path := m_get_string(m, "path")
		if path != "" {
			append(&out, Include{
				path = path,
				relative_paths = value_bool(m_get_or(m, "relativePaths", true), true),
				enable = include_enabled(m_get_or(m, "enable", true)),
			})
		}
	}
	return out[:]
}

include_enabled :: proc(v: Value) -> bool {
	if s, ok := v.(string); ok {
		l, _ := strings.to_lower(strings.trim_space(s))
		return l == "true" || l == "yes" || l == "1" || l == "on"
	}
	return value_bool(v, true)
}

m_get_or :: proc(m: Map, key: string, default: Value) -> Value {
	if v, ok := m_get(m, key); ok do return v
	return default
}

expand_env :: proc(v: Value) -> Value {
	#partial switch x in v {
	case string:
		return expand_env_string(x)
	case []Value:
		out := make([]Value, len(x))
		for item, i in x do out[i] = expand_env(item)
		return out
	case Map:
		out := m_empty()
		for k in x.keys {
			new_key := expand_env_string(k)
			m_set(&out, new_key, expand_env(x.values[k]))
		}
		return out
	case:
		return v
	}
}

expand_env_string :: proc(s: string) -> string {
	if !strings.contains(s, "${") do return s
	out := strings.Builder{}
	strings.builder_init(&out)
	i := 0
	for i < len(s) {
		if i + 1 < len(s) && s[i] == '$' && s[i + 1] == '{' {
			end := -1
			for j := i + 2; j < len(s); j += 1 {
				if s[j] == '}' {
					end = j
					break
				}
			}
			if end > i + 2 {
				name := s[i + 2:end]
				if value, found := os.lookup_env(name, context.allocator); found {
					strings.write_string(&out, value)
					i = end + 1
					continue
				}
			}
		}
		strings.write_byte(&out, s[i])
		i += 1
	}
	return strings.to_string(out)
}

rewrite_paths :: proc(v: Value, prefix: string) -> Value {
	if prefix == "" || prefix == "." do return value_clone(v)
	#partial switch x in v {
	case []Value:
		out := make([]Value, len(x))
		for item, i in x do out[i] = rewrite_paths(item, prefix)
		return out
	case Map:
		out := m_empty()
		for k in x.keys {
			vv := x.values[k]
			switch k {
			case "path", "manifest", "res", "java", "jni_libs", "proguard",
			     "storeFile", "outputDirectory", "workingDirectory", "carthageBuildPath",
			     "framework", "xcconfig", "testPlan", "scheme", "project",
			     "command", "output":
				if s, ok := vv.(string); ok {
					m_set(&out, strings.clone(k), join_prefix(prefix, s))
					continue
				}
			case "configFiles":
				if cm, ok := vv.(Map); ok {
					nm := m_empty()
					for ck in cm.keys {
						if s, ok2 := cm.values[ck].(string); ok2 {
							m_set(&nm, strings.clone(ck), join_prefix(prefix, s))
						} else {
							m_set(&nm, strings.clone(ck), rewrite_paths(cm.values[ck], prefix))
						}
					}
					m_set(&out, strings.clone(k), nm)
					continue
				}
			case "fileGroups":
				if arr, ok := vv.([]Value); ok {
					na := make([]Value, len(arr))
					for item, i in arr {
						if s, ok2 := item.(string); ok2 {
							na[i] = join_prefix(prefix, s)
						} else {
							na[i] = rewrite_paths(item, prefix)
						}
					}
					m_set(&out, strings.clone(k), na)
					continue
				}
			case "sources", "inputs", "inputFiles", "outputFiles", "inputFileLists", "outputFileLists":
				if s, ok := vv.(string); ok {
					m_set(&out, strings.clone(k), join_prefix(prefix, s))
					continue
				}
				if arr, ok := vv.([]Value); ok {
					na := make([]Value, len(arr))
					for item, i in arr {
						if s, ok2 := item.(string); ok2 {
							na[i] = join_prefix(prefix, s)
						} else {
							na[i] = rewrite_paths(item, prefix)
						}
					}
					m_set(&out, strings.clone(k), na)
					continue
				}
			case "include":
				m_set(&out, strings.clone(k), vv)
				continue
			}
			m_set(&out, strings.clone(k), rewrite_paths(vv, prefix))
		}
		return out
	case:
		return v
	}
}

join_prefix :: proc(prefix, path: string) -> string {
	if path == "" do return path
	if filepath.is_abs(path) do return path
	if strings.has_prefix(path, "~") || strings.has_prefix(path, "$") do return path
	return join_path(prefix, path)
}

is_abs_path :: proc(path: string) -> bool {
	return filepath.is_abs(path)
}

join_path :: proc(a, b: string) -> string {
	return join_paths(a, b)
}

join_paths :: proc(parts: ..string) -> string {
	res, err := filepath.join(parts)
	if err == nil do return res
	return strings.join(parts, "/")
}

yaml_dump_value :: proc(v: Value) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	yaml_dump_into(&out, v, 0, false)
	return strings.to_string(out)
}

yaml_dump_into :: proc(out: ^strings.Builder, v: Value, indent: int, in_array: bool) {
	#partial switch x in v {
	case Map:
		if len(x.keys) == 0 {
			strings.write_string(out, "{}")
			if !in_array do strings.write_byte(out, '\n')
			return
		}
		first := true
		for k in x.keys {
			if !first || !in_array do strings_write_indent(out, indent)
			first = false
			strings.write_string(out, yaml_quote_key(k))
			strings.write_string(out, ":")
			vv := x.values[k]
			if is_scalar(vv) {
				strings.write_byte(out, ' ')
				strings.write_string(out, yaml_scalar_repr(vv))
				strings.write_byte(out, '\n')
			} else {
				strings.write_byte(out, '\n')
				yaml_dump_into(out, vv, indent + 2, false)
			}
		}
	case []Value:
		if len(x) == 0 {
			strings.write_string(out, "[]")
			if !in_array do strings.write_byte(out, '\n')
			return
		}
		for item in x {
			if !in_array do strings_write_indent(out, indent)
			strings.write_string(out, "-")
			if is_scalar(item) {
				strings.write_byte(out, ' ')
				strings.write_string(out, yaml_scalar_repr(item))
				strings.write_byte(out, '\n')
			} else if m, ok := item.(Map); ok {
				// Inline the first key after the dash for readability.
				if len(m.keys) > 0 {
					first_key := m.keys[0]
					strings.write_byte(out, ' ')
					strings.write_string(out, yaml_quote_key(first_key))
					strings.write_string(out, ":")
					fv := m.values[first_key]
					if is_scalar(fv) {
						strings.write_byte(out, ' ')
						strings.write_string(out, yaml_scalar_repr(fv))
						strings.write_byte(out, '\n')
					} else {
						strings.write_byte(out, '\n')
						yaml_dump_into(out, fv, indent + 4, false)
					}
					for ki in 1 ..< len(m.keys) {
						k := m.keys[ki]
						strings_write_indent(out, indent + 2)
						strings.write_string(out, yaml_quote_key(k))
						strings.write_string(out, ":")
						kv := m.values[k]
						if is_scalar(kv) {
							strings.write_byte(out, ' ')
							strings.write_string(out, yaml_scalar_repr(kv))
							strings.write_byte(out, '\n')
						} else {
							strings.write_byte(out, '\n')
							yaml_dump_into(out, kv, indent + 4, false)
						}
					}
				} else {
					strings.write_byte(out, '\n')
				}
			} else {
				strings.write_byte(out, '\n')
				yaml_dump_into(out, item, indent + 2, false)
			}
		}
	case:
		strings_write_indent(out, indent)
		strings.write_string(out, yaml_scalar_repr(v))
		strings.write_byte(out, '\n')
	}
}

strings_write_indent :: proc(out: ^strings.Builder, n: int) {
	for _ in 0 ..< n do strings.write_byte(out, ' ')
}

is_scalar :: proc(v: Value) -> bool {
	if _, ok := v.(Map); ok do return false
	if _, ok := v.([]Value); ok do return false
	return true
}

yaml_scalar_repr :: proc(v: Value) -> string {
	#partial switch x in v {
	case string:
		return yaml_quote_string(x)
	case bool:
		return "true" if x else "false"
	case i64:
		return fmt.tprintf("%d", x)
	case f64:
		return value_string(x)
	case:
		return "null"
	}
}

yaml_quote_key :: proc(s: string) -> string {
	if yaml_plain_ok(s) do return s
	return yaml_quote_string(s)
}

yaml_plain_ok :: proc(s: string) -> bool {
	if len(s) == 0 do return false
	if strings.contains_any(s, ":#[]{},&*!|>'\"%@`") do return false
	if s[0] == '-' || s[0] == '?' || s[0] == ' ' do return false
	l, _ := strings.to_lower(s)
	if l == "true" || l == "false" || l == "null" || l == "yes" || l == "no" || l == "on" || l == "off" do return false
	return true
}

yaml_quote_string :: proc(s: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	strings.write_byte(&out, '"')
	for c in s {
		switch c {
		case '"':
			strings.write_string(&out, "\\\"")
		case '\\':
			strings.write_string(&out, "\\\\")
		case '\n':
			strings.write_string(&out, "\\n")
		case '\r':
			strings.write_string(&out, "\\r")
		case '\t':
			strings.write_string(&out, "\\t")
		case:
			strings.write_rune(&out, c)
		}
	}
	strings.write_byte(&out, '"')
	return strings.to_string(out)
}

json_dump_value :: proc(v: Value) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	json_dump_into(&out, v, 0)
	return strings.to_string(out)
}

json_dump_into :: proc(out: ^strings.Builder, v: Value, indent: int) {
	#partial switch x in v {
	case Map:
		strings.write_byte(out, '{')
		if len(x.keys) > 0 {
			strings.write_byte(out, '\n')
			for k, i in x.keys {
				strings_write_indent(out, indent + 2)
				strings.write_string(out, yaml_quote_string(k))
				strings.write_string(out, ": ")
				json_dump_into(out, x.values[k], indent + 2)
				if i < len(x.keys) - 1 do strings.write_byte(out, ',')
				strings.write_byte(out, '\n')
			}
			strings_write_indent(out, indent)
		}
		strings.write_byte(out, '}')
	case []Value:
		strings.write_byte(out, '[')
		if len(x) > 0 {
			strings.write_byte(out, '\n')
			for item, i in x {
				strings_write_indent(out, indent + 2)
				json_dump_into(out, item, indent + 2)
				if i < len(x) - 1 do strings.write_byte(out, ',')
				strings.write_byte(out, '\n')
			}
			strings_write_indent(out, indent)
		}
		strings.write_byte(out, ']')
	case string:
		strings.write_string(out, yaml_quote_string(x))
	case bool:
		strings.write_string(out, "true" if x else "false")
	case i64:
		strings.write_string(out, fmt.tprintf("%d", x))
	case f64:
		strings.write_string(out, fmt.tprintf("%g", x))
	case:
		strings.write_string(out, "null")
	}
}
