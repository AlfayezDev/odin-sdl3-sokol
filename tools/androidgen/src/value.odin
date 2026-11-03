package androidgen

import "core:fmt"
import "core:strconv"
import "core:strings"

// Ordered YAML/JSON value tree. Maps preserve insertion order so generated
// output and target ordering are deterministic.
Value :: union {
	bool,
	i64,
	f64,
	string,
	[]Value,
	Map,
}

Map :: struct {
	keys:   [dynamic]string,
	values: map[string]Value,
}

m_empty :: proc() -> Map {
	return Map {
		keys   = make([dynamic]string),
		values = make(map[string]Value),
	}
}

m_has :: proc(m: Map, key: string) -> bool {
	_, ok := m.values[key]
	return ok
}

m_get :: proc(m: Map, key: string) -> (Value, bool) {
	v, ok := m.values[key]
	return v, ok
}

m_get_string :: proc(m: Map, key: string) -> string {
	if v, ok := m.values[key]; ok {
		return value_string(v)
	}
	return ""
}

m_get_string_or :: proc(m: Map, key, default: string) -> string {
	if v, ok := m.values[key]; ok {
		s := value_string(v)
		if s != "" do return s
	}
	return default
}

m_set :: proc(m: ^Map, key: string, v: Value) {
	if _, ok := m.values[key]; !ok {
		append(&m.keys, key)
	}
	m.values[key] = v
}


m_clone :: proc(m: Map) -> Map {
	out := m_empty()
	for k in m.keys {
		m_set(&out, strings.clone(k), value_clone(m.values[k]))
	}
	return out
}

value_is_null :: proc(v: Value) -> bool {
	return v == nil
}

value_is_map :: proc(v: Value) -> bool {
	_, ok := v.(Map)
	return ok
}

value_is_array :: proc(v: Value) -> bool {
	_, ok := v.([]Value)
	return ok
}

value_map :: proc(v: Value) -> (Map, bool) {
	if m, ok := v.(Map); ok do return m, true
	return {}, false
}

value_array :: proc(v: Value) -> ([]Value, bool) {
	if a, ok := v.([]Value); ok do return a, true
	return nil, false
}

value_bool :: proc(v: Value, default := false) -> bool {
	#partial switch x in v {
	case bool:
		return x
	case string:
		s, _ := strings.to_lower(strings.trim_space(x))
		return s == "true" || s == "yes" || s == "y" || s == "on" || s == "1"
	case i64:
		return x != 0
	case f64:
		return x != 0
	case:
		return default
	}
}

value_int :: proc(v: Value, default := 0) -> int {
	#partial switch x in v {
	case i64:
		return int(x)
	case f64:
		return int(x)
	case string:
		s := strings.trim_space(x)
		if n, ok := strconv.parse_i64(s); ok do return int(n)
		if f, ok := strconv.parse_f64(s); ok do return int(f)
	case:
		return default
	}
	return default
}

value_string :: proc(v: Value) -> string {
	switch x in v {
	case string:
		return x
	case bool:
		return "true" if x else "false"
	case i64:
		return fmt.tprintf("%d", x)
	case f64:
		// YAML/JSON numbers used as versions should not gain trailing zeros.
		if x == f64(i64(x)) {
			return fmt.tprintf("%.1f", x)
		}
		return fmt.tprintf("%g", x)
	case []Value:
		return ""
	case Map:
		return ""
	}
	return ""
}

value_float :: proc(v: Value, default := 0.0) -> f64 {
	#partial switch x in v {
	case f64:
		return x
	case i64:
		return f64(x)
	case string:
		if f, ok := strconv.parse_f64(strings.trim_space(x)); ok do return f
	case:
		return default
	}
	return default
}

value_clone :: proc(v: Value) -> Value {
	switch x in v {
	case string:
		return strings.clone(x)
	case []Value:
		out := make([]Value, len(x))
		for item, i in x do out[i] = value_clone(item)
		return out
	case Map:
		return m_clone(x)
	case bool:
		return x
	case i64:
		return x
	case f64:
		return x
	}
	return nil
}

// Merge `over` on top of `base`. Maps merge recursively, arrays append,
// scalars replace. A key ending in ":REPLACE" replaces the existing value
// wholesale, matching XcodeGen's include semantics.
value_merge :: proc(base, over: Value) -> Value {
	bm, b_ok := base.(Map)
	om, o_ok := over.(Map)
	if b_ok && o_ok {
		return m_merge(bm, om)
	}
	return value_clone(over)
}

m_merge :: proc(base, over: Map) -> Map {
	out := m_clone(base)
	for k in over.keys {
		v := over.values[k]
		key := k
		replace := false
		if strings.has_suffix(k, ":REPLACE") {
			key = k[:len(k) - len(":REPLACE")]
			replace = true
		}
		existing, exists := out.values[key]
		if replace || !exists {
			m_set(&out, strings.clone(key), value_clone(v))
			continue
		}
		b_arr, b_is_arr := existing.([]Value)
		n_arr, n_is_arr := v.([]Value)
		if b_is_arr && n_is_arr {
			combined := make([dynamic]Value, 0)
			for item in b_arr do append(&combined, value_clone(item))
			for item in n_arr do append(&combined, value_clone(item))
			m_set(&out, strings.clone(key), combined[:])
			continue
		}
		b_map, b_is_map := existing.(Map)
		n_map, n_is_map := v.(Map)
		if b_is_map && n_is_map {
			m_set(&out, strings.clone(key), m_merge(b_map, n_map))
			continue
		}
		m_set(&out, strings.clone(key), value_clone(v))
	}
	return out
}

value_array_strings :: proc(v: Value) -> []string {
	if s, ok := v.(string); ok {
		out := make([]string, 1)
		out[0] = s
		return out
	}
	if a, ok := v.([]Value); ok {
		out := make([dynamic]string)
		for item in a {
			if s, ok2 := item.(string); ok2 do append(&out, s)
		}
		return out[:]
	}
	return nil
}



string_array_contains :: proc(arr: []string, needle: string) -> bool {
	for s in arr {
		if s == needle do return true
	}
	return false
}

sorted_string_map_keys :: proc(m: map[string]string) -> []string {
	out := make([dynamic]string)
	for k in m do append(&out, k)
	sort_strings(out[:])
	return out[:]
}

sorted_keys :: proc(m: Map) -> []string {
	out := make([]string, len(m.keys))
	copy(out, m.keys[:])
	sort_strings(out)
	return out
}

sort_strings :: proc(arr: []string) {
	for i in 1 ..< len(arr) {
		j := i
		for j > 0 && arr[j - 1] > arr[j] {
			arr[j - 1], arr[j] = arr[j], arr[j - 1]
			j -= 1
		}
	}
}
