package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Binding_Config :: struct {
	name:             string,
	source:           string,
	source_language:  string,
	functions:        []Binding_Func,
	header:           string,
	odin:             string,
	kotlin:           string,
	jni:              string,
	java_package:     string,
	class:            string,
	odin_lib:         string,
	platform_handler: bool,
}

Binding_Param :: struct {
	name: string,
	typ:  string,
}

Binding_Func :: struct {
	name:      string,
	ret:       string,
	params:    [dynamic]Binding_Param,
	is_export: bool,
}

Binding_IDL :: struct {
	name:    string,
	pkg:     string,
	class:   string,
	funcs:   []Binding_Func,
}

parse_bindings :: proc(m: Map, project: ^Project, disable_env: bool) -> ([]Binding_Config, string) {
	v, has := m_get(m, "bindings")
	if !has do return nil, ""
	out := make([dynamic]Binding_Config)
	if bm, ok := v.(Map); ok {
		if m_has(bm, "source") {
			cfg, err := parse_binding_config(bm, "", project, disable_env)
			if err != "" do return nil, err
			append(&out, cfg)
		} else {
			for name in bm.keys {
				entry, ok2 := bm.values[name].(Map)
				if !ok2 do return nil, fmt.tprintf("bindings.%s must be a mapping", name)
				cfg, err := parse_binding_config(entry, name, project, disable_env)
				if err != "" do return nil, err
				append(&out, cfg)
			}
		}
	} else if arr, ok := v.([]Value); ok {
		for item, i in arr {
			entry, ok2 := item.(Map)
			if !ok2 do return nil, fmt.tprintf("bindings[%d] must be a mapping", i)
			cfg, err := parse_binding_config(entry, "", project, disable_env)
			if err != "" do return nil, err
			append(&out, cfg)
		}
	} else {
		return nil, "bindings must be a mapping or a list"
	}
	return out[:], ""
}

parse_binding_config :: proc(m: Map, fallback_name: string, project: ^Project, disable_env: bool) -> (Binding_Config, string) {
	source := m_get_string(m, "source")
	language := m_get_string(m, "sourceLanguage")
	if language == "" do language = m_get_string(m, "language")
	if language == "" {
		if strings.has_suffix(strings.to_lower(source), ".odin") {
			language = "odin"
		} else {
			language = "idl"
		}
	}
	if language != "idl" && language != "odin" {
		return {}, fmt.tprintf("bindings: unsupported sourceLanguage %q (expected idl or odin)", language)
	}

	funcs: []Binding_Func
	idl := Binding_IDL{}
	abs_source := ""
	if source != "" {
		abs_source = resolve_binding_path(project, source)
		if !os.is_file(abs_source) do return {}, fmt.tprintf("bindings: source does not exist: %s", abs_source)
		if language == "odin" {
			parsed, err := parse_odin_binding_source(abs_source)
			if err != "" do return {}, err
			funcs = parsed
		} else {
			parsed, err := parse_binding_idl(abs_source, disable_env)
			if err != "" do return {}, err
			idl = parsed
			funcs = parsed.funcs
		}
	} else if language == "idl" {
		if fv, has := m_get(m, "functions"); has {
			parsed, err := parse_binding_functions(fv)
			if err != "" do return {}, err
			funcs = parsed
		} else {
			return {}, "bindings entry needs source or functions"
		}
	} else {
		return {}, "bindings entry is missing source"
	}

	name := m_get_string(m, "name")
	if name == "" do name = fallback_name
	if name == "" do name = idl.name
	if name == "" && abs_source != "" {
		base := filepath.base(abs_source)
		name = strings.trim_suffix(base, filepath.ext(base))
	}
	if name == "" do name = "bridge"

	class := m_get_string(m, "class")
	if class == "" do class = idl.class
	if class == "" do class = pascal_case(name)

	package_name := m_get_string(m, "package")
	if package_name == "" do package_name = idl.pkg
	if package_name == "" do package_name = default_binding_package(project)
	if package_name == "" do return {}, fmt.tprintf("bindings.%s: package is required (or set an application namespace)", name)

	cfg := Binding_Config{
		name = name,
		source = abs_source,
		source_language = language,
		functions = funcs,
		class = class,
		java_package = package_name,
		platform_handler = value_bool(m_get_or(m, "platformHandler", true), true),
	}
	cfg.header = resolve_binding_path(project, m_get_string_or(m, "header", join_path("binding/api", fmt.tprintf("%s.h", name))))
	package_path, _ := strings.replace_all(package_name, ".", "/")
	cfg.kotlin = resolve_binding_path(project, m_get_string_or(m, "kotlin", join_path(join_path("binding/android/java", package_path), fmt.tprintf("%s.kt", class))))
	cfg.jni = resolve_binding_path(project, m_get_string_or(m, "jni", join_path("binding/android/native", fmt.tprintf("%s_jni.c", name))))
	if m_has(m, "odin") {
		cfg.odin = resolve_binding_path(project, m_get_string(m, "odin"))
	} else if language == "odin" {
		cfg.odin = resolve_binding_path(project, join_path(join_path("vendors", name), fmt.tprintf("%s.odin", name)))
	}
	cfg.odin_lib = m_get_string(m, "odinLib")
	if cfg.odin_lib != "" do cfg.odin_lib = resolve_binding_path(project, cfg.odin_lib)
	return cfg, ""
}

default_binding_package :: proc(project: ^Project) -> string {
	for t in project.targets {
		if t.kind == .Application {
			if t.android.namespace != "" do return t.android.namespace
			if t.android.application_id != "" do return t.android.application_id
		}
	}
	return ""
}

parse_binding_idl :: proc(path: string, disable_env: bool) -> (Binding_IDL, string) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return {}, fmt.tprintf("cannot read binding IDL: %s", path)
	parsed, perr := parse_spec_text(string(data), path)
	if perr != "" do return {}, fmt.tprintf("%s: %s", path, perr)
	if !disable_env do parsed = expand_env(parsed)
	m, ok := parsed.(Map)
	if !ok do return {}, fmt.tprintf("%s: binding IDL root must be a mapping", path)
	idl := Binding_IDL{
		name = m_get_string(m, "name"),
		pkg = m_get_string(m, "package"),
		class = m_get_string(m, "class"),
	}
	fv, has := m_get(m, "functions")
	if !has do return {}, fmt.tprintf("%s: binding IDL has no functions", path)
	funcs, ferr := parse_binding_functions(fv)
	if ferr != "" do return {}, fmt.tprintf("%s: %s", path, ferr)
	idl.funcs = funcs
	return idl, ""
}

parse_binding_functions :: proc(v: Value) -> ([]Binding_Func, string) {
	arr, ok := v.([]Value)
	if !ok do return nil, "functions must be a list"
	funcs := make([dynamic]Binding_Func)
	for item, idx in arr {
		m, ok2 := item.(Map)
		if !ok2 do return nil, fmt.tprintf("functions[%d] must be a mapping", idx)
		name := m_get_string(m, "name")
		if name == "" do return nil, fmt.tprintf("functions[%d] is missing name", idx)
		direction := m_get_string_or(m, "direction", "export")
		is_export := false
		switch direction {
		case "export", "native", "out":
			is_export = true
		case "import", "platform", "kotlin", "in":
			is_export = false
		case:
			return nil, fmt.tprintf("%s: invalid direction %q", name, direction)
		}
		ret := m_get_string(m, "returns")
		if ret == "" do ret = m_get_string(m, "return")
		if ret == "void" do ret = ""
		if ret != "" {
			if err := binding_check_type(ret, fmt.tprintf("%s return", name)); err != "" do return nil, err
		}
		f := Binding_Func{name = name, ret = ret, is_export = is_export, params = make([dynamic]Binding_Param)}
		pv, has_params := m_get(m, "params")
		if !has_params do pv, has_params = m_get(m, "parameters")
		if has_params {
			parr, ok3 := pv.([]Value)
			if !ok3 do return nil, fmt.tprintf("%s: params must be a list", name)
			for pitem, pidx in parr {
				pm, ok4 := pitem.(Map)
				if !ok4 do return nil, fmt.tprintf("%s: params[%d] must be a mapping", name, pidx)
				pname := m_get_string(pm, "name")
				ptype := m_get_string(pm, "type")
				if pname == "" || ptype == "" do return nil, fmt.tprintf("%s: params[%d] needs name and type", name, pidx)
				if err := binding_check_type(ptype, fmt.tprintf("%s(%s)", name, pname)); err != "" do return nil, err
				append(&f.params, Binding_Param{name = pname, typ = ptype})
			}
		}
		for existing in funcs {
			if existing.name == f.name do return nil, fmt.tprintf("duplicate binding %s", f.name)
		}
		append(&funcs, f)
	}
	if len(funcs) == 0 do return nil, "functions list is empty"
	return funcs[:], ""
}

resolve_binding_path :: proc(project: ^Project, path: string) -> string {
	if path == "" do return ""
	if filepath.is_abs(path) do return clean_path(path)
	return clean_path(join_path(project.base_dir, path))
}

pascal_case :: proc(s: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	upper := true
	for c in s {
		if c == '_' || c == '-' || c == '.' || c == '/' {
			upper = true
			continue
		}
		if upper && c >= 'a' && c <= 'z' {
			strings.write_byte(&out, byte(c - ('a' - 'A')))
		} else {
			strings.write_rune(&out, c)
		}
		upper = false
	}
	res := strings.to_string(out)
	if res == "" do return "Bridge"
	return res
}

binding_camel :: proc(s: string) -> string {
	parts := strings.split(s, "_")
	out := parts[0]
	for p, i in parts {
		if i == 0 || len(p) == 0 do continue
		up := p[0]
		if up >= 'a' && up <= 'z' do up -= 'a' - 'A'
		out = fmt.tprintf("%s%c%s", out, rune(up), p[1:])
	}
	return out
}

binding_check_type :: proc(t, site: string) -> string {
	switch t {
	case "cstring", "i32", "i64", "b32", "f32", "f64":
		return ""
	}
	return fmt.tprintf("unknown type %q (%s); supported: cstring, i32, i64, b32, f32, f64", t, site)
}

parse_odin_binding_source :: proc(path: string) -> ([]Binding_Func, string) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return nil, fmt.tprintf("cannot read binding source: %s", path)
	funcs := make([dynamic]Binding_Func)
	lines := strings.split(string(data), "\n")
	skipping_body := false
	for l, idx in lines {
		line := strings.trim_space(l)
		if skipping_body {
			if l == "}" do skipping_body = false
			continue
		}
		if len(line) == 0 || line[0] == '/' || line[0] == '*' || line[0] == '#' || strings.has_prefix(line, "@(") do continue
		if !strings.contains(line, ":: proc \"c\"") do continue
		f, ok, perr := parse_binding_proc_line(line, idx + 1)
		if perr != "" do return nil, fmt.tprintf("%s:%d: %s", path, idx + 1, perr)
		if !ok do continue
		for existing in funcs {
			if existing.name == f.name do return nil, fmt.tprintf("%s:%d: duplicate binding %s", path, idx + 1, f.name)
		}
		if f.is_export do skipping_body = true
		append(&funcs, f)
	}
	if len(funcs) == 0 do return nil, fmt.tprintf("no `:: proc \"c\"` declarations found in %s", path)
	return funcs[:], ""
}

parse_binding_proc_line :: proc(line_in: string, lineno: int) -> (Binding_Func, bool, string) {
	line := line_in
	if idx := strings.index(line, "//"); idx >= 0 do line = line[:idx]
	line = strings.trim_space(line)
	sep := strings.index_byte(line, ':')
	if sep < 0 do return {}, false, "cannot parse proc line"
	name := strings.trim_space(line[:sep])
	open := strings.index_byte(line, '(')
	close := strings.last_index_byte(line, ')')
	if open < 0 || close < open do return {}, false, "cannot parse proc parameters"
	inner := strings.trim_space(line[open + 1:close])
	tail := strings.trim_space(line[close + 1:])
	f := Binding_Func{name = name, params = make([dynamic]Binding_Param)}
	f.is_export = strings.has_suffix(tail, "{")
	if strings.has_prefix(tail, "->") {
		ret := strings.trim_space(tail[2:])
		if f.is_export {
			ret = strings.trim_space(strings.trim_suffix(ret, "{"))
		} else {
			ret = strings.trim_space(strings.trim_suffix(ret, "---"))
		}
		if err := binding_check_type(ret, fmt.tprintf("%s return", name)); err != "" do return {}, false, err
		f.ret = ret
	}
	if len(inner) > 0 {
		pending := make([dynamic]string)
		for p in strings.split(inner, ",") {
			pt := strings.trim_space(p)
			if len(pt) == 0 do continue
			colon := strings.index_byte(pt, ':')
			if colon >= 0 {
				pname := strings.trim_space(pt[:colon])
				ptype := strings.trim_space(pt[colon + 1:])
				if err := binding_check_type(ptype, fmt.tprintf("%s(%s)", name, pname)); err != "" do return {}, false, err
				for pn in pending do append(&f.params, Binding_Param{name = pn, typ = ptype})
				clear(&pending)
				append(&f.params, Binding_Param{name = pname, typ = ptype})
			} else {
				append(&pending, pt)
			}
		}
		if len(pending) > 0 do return {}, false, fmt.tprintf("parameters without a type: %s", strings.join(pending[:], ", "))
	}
	return f, true, ""
}

binding_c_type :: proc(t: string) -> string {
	switch t {
	case "cstring": return "const char *"
	case "i32": return "int32_t"
	case "i64": return "int64_t"
	case "b32": return "int32_t"
	case "f32": return "float"
	case "f64": return "double"
	}
	return "void"
}

binding_kotlin_type :: proc(t: string) -> string {
	switch t {
	case "cstring": return "String"
	case "i32": return "Int"
	case "i64": return "Long"
	case "b32": return "Boolean"
	case "f32": return "Float"
	case "f64": return "Double"
	}
	return "Unit"
}

binding_jni_type :: proc(t: string) -> string {
	switch t {
	case "cstring": return "jstring"
	case "i32": return "jint"
	case "i64": return "jlong"
	case "b32": return "jboolean"
	case "f32": return "jfloat"
	case "f64": return "jdouble"
	}
	return "void"
}

binding_jni_sig :: proc(t: string) -> string {
	switch t {
	case "cstring": return "Ljava/lang/String;"
	case "i32": return "I"
	case "i64": return "J"
	case "b32": return "Z"
	case "f32": return "F"
	case "f64": return "D"
	}
	return "V"
}

binding_jni_call :: proc(t: string) -> string {
	switch t {
	case "i32": return "CallStaticIntMethod"
	case "i64": return "CallStaticLongMethod"
	case "b32": return "CallStaticBooleanMethod"
	case "f32": return "CallStaticFloatMethod"
	case "f64": return "CallStaticDoubleMethod"
	}
	return "CallStaticVoidMethod"
}

binding_default_value :: proc(t: string) -> string {
	switch t {
	case "i32": return "0"
	case "i64": return "0L"
	case "b32": return "false"
	case "f32": return "0f"
	case "f64": return "0.0"
	}
	return ""
}

generate_bindings :: proc(project: ^Project) -> string {
	for cfg in project.bindings {
		if err := generate_binding(project, cfg); err != "" do return err
	}
	return ""
}

generate_binding :: proc(project: ^Project, cfg: Binding_Config) -> string {
	funcs := cfg.functions
	if len(funcs) == 0 {
		if cfg.source == "" do return fmt.tprintf("bindings.%s: no functions or source", cfg.name)
		if cfg.source_language == "odin" {
			parsed, err := parse_odin_binding_source(cfg.source)
			if err != "" do return err
			funcs = parsed
		} else {
			parsed, err := parse_binding_idl(cfg.source, false)
			if err != "" do return err
			funcs = parsed.funcs
		}
	}
	for f in funcs {
		if !f.is_export && f.ret == "cstring" {
			return fmt.tprintf("bindings.%s: import %s cannot return cstring", cfg.name, f.name)
		}
	}
	if herr := emit_binding_header(cfg, funcs); herr != "" do return herr
	if cfg.odin != "" {
		if oerr := emit_binding_odin(cfg, funcs); oerr != "" do return oerr
	}
	if kerr := emit_binding_kotlin(cfg, funcs); kerr != "" do return kerr
	if jerr := emit_binding_jni(cfg, funcs); jerr != "" do return jerr
	return ""
}

emit_binding_header :: proc(cfg: Binding_Config, funcs: []Binding_Func) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	guard := strings.to_upper(strings.trim_suffix(filepath.base(cfg.header), filepath.ext(cfg.header)))
	guard, _ = strings.replace_all(guard, "-", "_")
	guard, _ = strings.replace_all(guard, ".", "_")
	guard = strings.concatenate([]string{guard, "_H"})
	line(&b, 0, "/* generated by androidgen bindings - do not edit by hand. */")
	line(&b, 0, fmt.tprintf("#ifndef %s", guard))
	line(&b, 0, fmt.tprintf("#define %s", guard))
	line(&b, 0, "")
	line(&b, 0, "#include <stdint.h>")
	line(&b, 0, "#include <stdbool.h>")
	line(&b, 0, "")
	line(&b, 0, "#ifdef __cplusplus")
	line(&b, 0, "extern \"C\" {")
	line(&b, 0, "#endif")
	line(&b, 1, "")
	line(&b, 0, "/* exports: implemented natively, consumed by Kotlin/Java */")
	for f in funcs {
		if !f.is_export do continue
		params := make([dynamic]string)
		for p in f.params do append(&params, fmt.tprintf("%s %s", binding_c_type(p.typ), p.name))
		args := "void"
		if len(params) > 0 do args = strings.join(params[:], ", ")
		line(&b, 0, fmt.tprintf("%s %s(%s);", binding_c_type(f.ret), f.name, args))
		line(&b, 0, "")
	}
	line(&b, 0, "/* imports: implemented by Kotlin/Java, called from native code */")
	for f in funcs {
		if f.is_export do continue
		params := make([dynamic]string)
		for p in f.params do append(&params, fmt.tprintf("%s %s", binding_c_type(p.typ), p.name))
		args := "void"
		if len(params) > 0 do args = strings.join(params[:], ", ")
		line(&b, 0, fmt.tprintf("%s %s(%s);", binding_c_type(f.ret), f.name, args))
		line(&b, 0, "")
	}
	line(&b, 0, "#ifdef __cplusplus")
	line(&b, 0, "}")
	line(&b, 0, "#endif")
	line(&b, 0, "")
	line(&b, 0, fmt.tprintf("#endif /* %s */", guard))
	return write_text_file(cfg.header, strings.to_string(b))
}

line :: proc(b: ^strings.Builder, indent: int, text: string) {
	for _ in 0 ..< indent * 4 do strings.write_byte(b, ' ')
	strings.write_string(b, text)
	strings.write_byte(b, '\n')
}

emit_binding_odin :: proc(cfg: Binding_Config, funcs: []Binding_Func) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	line(&b, 0, "// generated by androidgen bindings - do not edit by hand.")
	line(&b, 0, fmt.tprintf("package %s", sanitize_module_name(cfg.name)))
	line(&b, 0, "")
	if cfg.odin_lib != "" {
		line(&b, 0, fmt.tprintf("foreign import lib %q", cfg.odin_lib))
		line(&b, 0, "_ :: lib")
		line(&b, 0, "")
	}
	line(&b, 0, "@(default_calling_convention=\"c\")")
	line(&b, 0, "foreign {")
	for f in funcs {
		if f.is_export do continue
		params := make([dynamic]string)
		for p in f.params do append(&params, fmt.tprintf("%s: %s", p.name, p.typ))
		if f.ret == "" {
			line(&b, 1, fmt.tprintf("%s :: proc(%s) ---", f.name, strings.join(params[:], ", ")))
		} else {
			line(&b, 1, fmt.tprintf("%s :: proc(%s) -> %s ---", f.name, strings.join(params[:], ", "), f.ret))
		}
	}
	line(&b, 0, "}")
	return write_text_file(cfg.odin, strings.to_string(b))
}

emit_binding_kotlin :: proc(cfg: Binding_Config, funcs: []Binding_Func) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	line(&b, 0, fmt.tprintf("package %s", cfg.java_package))
	line(&b, 0, "")
	line(&b, 0, "// generated by androidgen bindings - do not edit by hand.")
	line(&b, 0, fmt.tprintf("object %s %s", cfg.class, "{"))
	if cfg.platform_handler {
		has_imports := false
		for f in funcs {
			if !f.is_export do has_imports = true
		}
		if has_imports {
			line(&b, 1, "interface PlatformHandler {")
			for f in funcs {
				if f.is_export do continue
				params := make([dynamic]string)
				for p in f.params do append(&params, fmt.tprintf("%s: %s", p.name, binding_kotlin_type(p.typ)))
				ret := ""
				if f.ret != "" do ret = strings.concatenate([]string{": ", binding_kotlin_type(f.ret)})
				line(&b, 2, fmt.tprintf("fun %s(%s)%s", binding_camel(f.name), strings.join(params[:], ", "), ret))
			}
			line(&b, 1, "}")
			line(&b, 1, "")
			line(&b, 1, "@JvmStatic var platform: PlatformHandler? = null")
			line(&b, 1, "")
		}
	}
	line(&b, 1, "// ---- Kotlin -> native (exports) ----")
	for f in funcs {
		if !f.is_export do continue
		params := make([dynamic]string)
		for p in f.params do append(&params, fmt.tprintf("%s: %s", p.name, binding_kotlin_type(p.typ)))
		ret := ""
		if f.ret != "" do ret = strings.concatenate([]string{": ", binding_kotlin_type(f.ret)})
		line(&b, 1, fmt.tprintf("@JvmStatic external fun %s(%s)%s", binding_camel(f.name), strings.join(params[:], ", "), ret))
	}
	line(&b, 1, "")
	line(&b, 1, "// ---- native -> Kotlin (imports) ----")
	for f in funcs {
		if f.is_export do continue
		params := make([dynamic]string)
		call_args := make([dynamic]string)
		for p in f.params {
			append(&params, fmt.tprintf("%s: %s", p.name, binding_kotlin_type(p.typ)))
			append(&call_args, p.name)
		}
		ret := ""
		if f.ret != "" do ret = strings.concatenate([]string{": ", binding_kotlin_type(f.ret)})
		line(&b, 1, fmt.tprintf("@JvmStatic fun %s(%s)%s %s", binding_camel(f.name), strings.join(params[:], ", "), ret, "{"))
		if f.ret == "" {
			line(&b, 2, fmt.tprintf("platform?.%s(%s)", binding_camel(f.name), strings.join(call_args[:], ", ")))
		} else {
			line(&b, 2, fmt.tprintf("return platform?.%s(%s) ?: %s", binding_camel(f.name), strings.join(call_args[:], ", "), binding_default_value(f.ret)))
		}
		line(&b, 1, "}")
	}
	line(&b, 0, "}")
	return write_text_file(cfg.kotlin, strings.to_string(b))
}

emit_binding_jni :: proc(cfg: Binding_Config, funcs: []Binding_Func) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	line(&b, 0, "// generated by androidgen bindings - do not edit by hand.")
	line(&b, 0, "#include <jni.h>")
	line(&b, 0, "#include <string.h>")
	include_path, rel_err := filepath.rel(filepath.dir(cfg.jni), cfg.header)
	if rel_err != nil do include_path = filepath.base(cfg.header)
	line(&b, 0, fmt.tprintf("#include %q", include_path))
	line(&b, 0, "")
	line(&b, 0, "static JavaVM *g_jvm;")
	line(&b, 0, "static jclass g_class;")
	for f in funcs {
		if f.is_export do continue
		line(&b, 0, fmt.tprintf("static jmethodID g_mid_%s;", binding_camel(f.name)))
	}
	line(&b, 0, "")
	line(&b, 0, "JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {")
	line(&b, 1, "(void)reserved;")
	line(&b, 1, "g_jvm = vm;")
	line(&b, 1, "JNIEnv *env = 0;")
	line(&b, 1, "if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;")
	class_path, _ := strings.replace_all(cfg.java_package, ".", "/")
	line(&b, 1, fmt.tprintf("jclass local = (*env)->FindClass(env, \"%s/%s\");", class_path, cfg.class))
	line(&b, 1, "if (!local) return JNI_ERR;")
	line(&b, 1, "g_class = (*env)->NewGlobalRef(env, local);")
	for f in funcs {
		if f.is_export do continue
		sigs := make([dynamic]string)
		for p in f.params do append(&sigs, binding_jni_sig(p.typ))
		kname := binding_camel(f.name)
		line(&b, 1, fmt.tprintf("g_mid_%s = (*env)->GetStaticMethodID(env, g_class, \"%s\", \"(%s)%s\");", kname, kname, strings.join(sigs[:], ""), binding_jni_sig(f.ret)))
		line(&b, 1, fmt.tprintf("if (!g_mid_%s) return JNI_ERR;", kname))
	}
	line(&b, 1, "(*env)->DeleteLocalRef(env, local);")
	line(&b, 1, "return JNI_VERSION_1_6;")
	line(&b, 0, "}")
	line(&b, 0, "")
	line(&b, 0, "static JNIEnv *bridge_env(void) {")
	line(&b, 1, "JNIEnv *env = 0;")
	line(&b, 1, "jint state = (*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6);")
	line(&b, 1, "#if defined(__ANDROID__)")
	line(&b, 1, "if (state == JNI_EDETACHED) (*g_jvm)->AttachCurrentThread(g_jvm, &env, 0);")
	line(&b, 1, "#else")
	line(&b, 1, "if (state == JNI_EDETACHED) (*g_jvm)->AttachCurrentThread(g_jvm, (void **)&env, 0);")
	line(&b, 1, "#endif")
	line(&b, 1, "return env;")
	line(&b, 0, "}")
	line(&b, 0, "")
	line(&b, 0, "// ---- Kotlin -> native (exports) ----")
	for f in funcs {
		if !f.is_export do continue
		kname := binding_camel(f.name)
		jni_params := make([dynamic]string)
		call_args := make([dynamic]string)
		prelude := make([dynamic]string)
		epilogue := make([dynamic]string)
		for p in f.params {
			append(&jni_params, fmt.tprintf("%s %s", binding_jni_type(p.typ), p.name))
			if p.typ == "cstring" {
				append(&prelude, fmt.tprintf("const char *p_%s = (*env)->GetStringUTFChars(env, %s, 0);", p.name, p.name))
				append(&call_args, fmt.tprintf("p_%s", p.name))
				append(&epilogue, fmt.tprintf("(*env)->ReleaseStringUTFChars(env, %s, p_%s);", p.name, p.name))
			} else if p.typ == "b32" {
				append(&prelude, fmt.tprintf("int32_t p_%s = %s ? 1 : 0;", p.name, p.name))
				append(&call_args, fmt.tprintf("p_%s", p.name))
			} else {
				append(&call_args, p.name)
			}
		}
		pkg_u, _ := strings.replace_all(cfg.java_package, ".", "_")
		line(&b, 0, fmt.tprintf("JNIEXPORT %s JNICALL Java_%s_%s_%s(JNIEnv *env, jclass clazz%s) %s", binding_jni_type(f.ret), pkg_u, cfg.class, kname, jni_param_suffix(jni_params[:]), "{"))
		line(&b, 1, "(void)clazz;")
		for pl in prelude do line(&b, 1, pl)
		call := fmt.tprintf("%s(%s)", f.name, strings.join(call_args[:], ", "))
		if f.ret == "" {
			line(&b, 1, fmt.tprintf("%s;", call))
			for ep in epilogue do line(&b, 1, ep)
		} else if f.ret == "cstring" {
			line(&b, 1, fmt.tprintf("const char *result = %s;", call))
			line(&b, 1, "jstring jresult = (*env)->NewStringUTF(env, result);")
			for ep in epilogue do line(&b, 1, ep)
			line(&b, 1, "return jresult;")
		} else if f.ret == "b32" {
			line(&b, 1, fmt.tprintf("int32_t result = %s;", call))
			for ep in epilogue do line(&b, 1, ep)
			line(&b, 1, "return result ? JNI_TRUE : JNI_FALSE;")
		} else {
			line(&b, 1, fmt.tprintf("%s result = %s;", binding_jni_type(f.ret), call))
			for ep in epilogue do line(&b, 1, ep)
			line(&b, 1, "return result;")
		}
		line(&b, 0, "}")
		line(&b, 0, "")
	}
	line(&b, 0, "// ---- native -> Kotlin (imports) ----")
	for f in funcs {
		if f.is_export do continue
		params := make([dynamic]string)
		for p in f.params do append(&params, fmt.tprintf("%s %s", binding_c_type(p.typ), p.name))
		args := "void"
		if len(params) > 0 do args = strings.join(params[:], ", ")
		line(&b, 0, fmt.tprintf("%s %s(%s) %s", binding_c_type(f.ret), f.name, args, "{"))
		line(&b, 1, "JNIEnv *env = bridge_env();")
		line(&b, 1, fmt.tprintf("if (!env || !g_mid_%s) return%s;", binding_camel(f.name), binding_return_default(f.ret)))
		call_args := make([dynamic]string)
		locals := make([dynamic]string)
		for p, idx in f.params {
			if p.typ == "cstring" {
				line(&b, 1, fmt.tprintf("jstring jarg%d = (*env)->NewStringUTF(env, %s);", idx, p.name))
				append(&call_args, fmt.tprintf("jarg%d", idx))
				append(&locals, fmt.tprintf("(*env)->DeleteLocalRef(env, jarg%d);", idx))
			} else if p.typ == "b32" {
				append(&call_args, fmt.tprintf("%s ? JNI_TRUE : JNI_FALSE", p.name))
			} else {
				append(&call_args, p.name)
			}
		}
		call := fmt.tprintf("(*env)->%s(env, g_class, g_mid_%s%s)", binding_jni_call(f.ret), binding_camel(f.name), jni_call_suffix(call_args[:]))
		if f.ret == "" {
			line(&b, 1, fmt.tprintf("%s;", call))
		} else if f.ret == "b32" {
			line(&b, 1, fmt.tprintf("jboolean result = %s;", call))
			line(&b, 1, "return result ? 1 : 0;")
		} else {
			line(&b, 1, fmt.tprintf("return %s;", call))
		}
		for l in locals do line(&b, 1, l)
		line(&b, 0, "}")
		line(&b, 0, "")
	}
	return write_text_file(cfg.jni, strings.to_string(b))
}

jni_param_suffix :: proc(params: []string) -> string {
	if len(params) == 0 do return ""
	return strings.concatenate([]string{", ", strings.join(params, ", ")})
}

jni_call_suffix :: proc(args: []string) -> string {
	if len(args) == 0 do return ""
	return strings.concatenate([]string{", ", strings.join(args, ", ")})
}

binding_return_default :: proc(t: string) -> string {
	switch t {
	case "i32": return " 0"
	case "i64": return " 0"
	case "b32": return " 0"
	case "f32": return " 0"
	case "f64": return " 0"
	}
	return ""
}
