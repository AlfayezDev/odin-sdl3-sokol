package bridgegen

// bridgegen: the single binding generator. The contract is an Odin file
// (app/bridge.odin): every `:: proc "c"` declaration in it is part of the
// cross-language API.
//
//   with body    -> odin export: Kotlin gets an `external fun`, platforms
//                   call the C symbol directly. Emits Java_<class>_<method>
//                   C wrappers.
//   without body -> platform import: Odin calls it via the generated
//                   foreign block; Android up-calls into Kotlin through
//                   the generated C implementation.
//
// Emits: C header (Swift bridging + JNI + desktop), Odin foreign block,
// Kotlin bridge object, JNI glue.
//
// Supported types: cstring, i32, i64, b32, f32, f64.
// Declarations must be single-line; export bodies must start with `{` on
// the declaration line and end with a line that is exactly `}`.
//
// usage:
//   bridgegen --source app/bridge.odin --hdr binding/api/bridge.h \
//             --odin vendors/bridge/bridge.odin \
//             --kt binding/android/java/dev/alfayez/odinsokol/OdinBridge.kt \
//             --jni build/gen/bridge_jni.c \
//             --package dev.alfayez.odinsokol --class OdinBridge

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

foreign {
	system :: proc "c" (command: cstring) -> c.int ---
}

jp :: proc(args: ..string) -> string {
	res, _ := filepath.join(args)
	return res
}

sh :: proc(cmd: string) -> bool {
	cs := strings.clone_to_cstring(cmd, context.temp_allocator)
	status := system(cs)
	if status != 0 {
		fmt.eprintln("FAILED:", cmd)
	}
	return status == 0
}

fail :: proc(msg: string) {
	fmt.eprintln("bridgegen:", msg)
	os.exit(1)
}

Param :: struct {
	name: string,
	typ:  string, // odin spelling: "cstring" "i32" "i64" "b32" "f32" "f64"
}

Func :: struct {
	name:      string,
	ret:       string, // same spellings; "" = void
	params:    [dynamic]Param,
	is_export: bool, // has a body
}

check_type :: proc(t: string, site: string) {
	ok := t == "cstring" || t == "i32" || t == "i64" || t == "b32" || t == "f32" || t == "f64"
	if !ok {
		fail(fmt.tprintf("unknown type '%s' (%s) — supported: cstring, i32, i64, b32, f32, f64", t, site))
	}
}

// snake_case -> camelCase ("show_toast" -> "showToast")
camel :: proc(s: string) -> string {
	parts := strings.split(s, "_")
	out := parts[0]
	for p, i in parts {
		if i == 0 || len(p) == 0 {
			continue
		}
		up := p[0]
		if up >= 'a' && up <= 'z' {
			up -= 'a' - 'A'
		}
		out = fmt.tprintf("%s%c%s", out, rune(up), p[1:])
	}
	return out
}

// ---- type maps: odin spelling -> per-language ----

c_type :: proc(t: string) -> string {
	if t == "cstring" {
		return "const char *"
	}
	if t == "i32" {
		return "int32_t"
	}
	if t == "i64" {
		return "int64_t"
	}
	if t == "b32" {
		return "bool"
	}
	if t == "f32" {
		return "float"
	}
	if t == "f64" {
		return "double"
	}
	return "void"
}

kotlin_type :: proc(t: string) -> string {
	if t == "cstring" {
		return "String"
	}
	if t == "i32" {
		return "Int"
	}
	if t == "i64" {
		return "Long"
	}
	if t == "b32" {
		return "Boolean"
	}
	if t == "f32" {
		return "Float"
	}
	if t == "f64" {
		return "Double"
	}
	return t
}

jni_type :: proc(t: string) -> string {
	if t == "cstring" {
		return "jstring"
	}
	if t == "i32" {
		return "jint"
	}
	if t == "i64" {
		return "jlong"
	}
	if t == "b32" {
		return "jboolean"
	}
	if t == "f32" {
		return "jfloat"
	}
	if t == "f64" {
		return "jdouble"
	}
	return "void"
}

jni_sig :: proc(t: string) -> string {
	if t == "cstring" {
		return "Ljava/lang/String;"
	}
	if t == "i32" {
		return "I"
	}
	if t == "i64" {
		return "J"
	}
	if t == "b32" {
		return "Z"
	}
	if t == "f32" {
		return "F"
	}
	if t == "f64" {
		return "D"
	}
	return "V"
}

// ---- parsing ----

// parse one `name :: proc "c" (params) -> ret [---|{|]` line
parse_proc_line :: proc(src, line_in: string, lineno: int) -> (f: Func, ok: bool) {
	line := strings.trim_space(line_in)
	if !strings.contains(line, ":: proc \"c\"") {
		return
	}
	sep := strings.index_byte(line, ':')
	name := strings.trim_space(line[:sep])
	rest := strings.trim_space(line[strings.index_byte(line, 'p'):])

	open := strings.index_byte(rest, '(')
	close := strings.last_index_byte(rest, ')')
	if open < 0 || close < open {
		fail(fmt.tprintf("%s:%d: cannot parse proc line: %s", src, lineno, line))
	}
	inner := strings.trim_space(rest[open + 1:close])
	tail := strings.trim_space(rest[close + 1:])

	// export = body opens on the declaration line; anything else = import
	is_export := strings.has_suffix(tail, "{")




	f.name = name
	f.params = make([dynamic]Param)
	f.is_export = is_export

	ret := ""
	if strings.has_prefix(tail, "->") {
		ret = strings.trim_space(tail[2:])
		if is_export {
			ret = strings.trim_suffix(ret, "{")
		} else {
			ret = strings.trim_suffix(ret, "---")
		}
		ret = strings.trim_space(ret)
	}
	if ret != "" {
		check_type(ret, fmt.tprintf("%s return", name))
		f.ret = ret
	}

	// params, with odin's grouped form: `a, b: i32`
	if len(inner) > 0 {
		pending := make([dynamic]string)
		for p in strings.split(inner, ",") {
			pt := strings.trim_space(p)
			if len(pt) == 0 {
				continue
			}
			colon := strings.index_byte(pt, ':')
			if colon >= 0 {
				pname := strings.trim_space(pt[:colon])
				ptype := strings.trim_space(pt[colon + 1:])
				check_type(ptype, fmt.tprintf("%s(%s)", name, pname))
				for pn in pending {
					append(&f.params, Param{pn, ptype})
				}
				clear(&pending)
				append(&f.params, Param{pname, ptype})
			} else {
				append(&pending, pt)
			}
		}
		if len(pending) > 0 {
			fail(fmt.tprintf("%s:%d: params '%s' have no type", src, lineno, strings.join(pending[:], ", ")))
		}
	}
	return f, true
}

parse_source :: proc(path: string) -> [dynamic]Func {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fail(fmt.tprintf("cannot read source %s", path))
	}
	funcs := make([dynamic]Func)
	lines := strings.split(string(data), "\n")
	skipping_body := false
	exports, imports := 0, 0
	for l, idx in lines {
		line := strings.trim_space(l)
		if skipping_body {
			if line == "}" {
				skipping_body = false
			}
			continue
		}
		if len(line) == 0 || line[0] == '/' || line[0] == '*' || line[0] == '#' || strings.has_prefix(line, "@(") {
			continue
		}
		if !strings.contains(line, ":: proc \"c\"") {
			continue
		}
		f, ok := parse_proc_line(path, line, idx + 1)
		if !ok {
			continue
		}
		if f.is_export {
			exports += 1
			skipping_body = true
		} else {
			imports += 1
		}
		append(&funcs, f)
	}
	if exports + imports == 0 {
		fail("no `:: proc \"c\"` declarations found in source")
	}
	fmt.println("bridgegen: parsed", exports, "export(s),", imports, "import(s)")
	return funcs
}

// ---- emitters ----

emit_header :: proc(path: string, funcs: [dynamic]Func) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "/* generated by bridgegen from app/bridge.odin — do not edit by hand.\n")
	strings.write_string(&b, "   the odin file is the source of truth; regenerate with: odin run . -- bridge */\n")
	strings.write_string(&b, "#ifndef BRIDGE_H\n#define BRIDGE_H\n\n#include <stdint.h>\n#include <stdbool.h>\n\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n")
	strings.write_string(&b, "/* exports: implemented in Odin, consumed by platforms */\n")
	for f in funcs {
		if !f.is_export {
			continue
		}
		cs := make([dynamic]string)
		for p in f.params {
			append(&cs, fmt.tprintf("%s %s", c_type(p.typ), p.name))
		}
		args := strings.join(cs[:], ", ")
		if len(cs) == 0 {
			args = "void"
		}
		strings.write_string(&b, fmt.tprintf("%s %s(%s);\n\n", c_type(f.ret), f.name, args))
	}
	strings.write_string(&b, "/* imports: implement these per platform */\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		cs := make([dynamic]string)
		for p in f.params {
			append(&cs, fmt.tprintf("%s %s", c_type(p.typ), p.name))
		}
		args := strings.join(cs[:], ", ")
		if len(cs) == 0 {
			args = "void"
		}
		strings.write_string(&b, fmt.tprintf("void %s(%s);\n\n", f.name, args))
	}
	strings.write_string(&b, "#ifdef __cplusplus\n}\n#endif\n\n#endif /* BRIDGE_H */\n")
	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

emit_odin :: proc(path: string, funcs: [dynamic]Func) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "// generated by bridgegen from app/bridge.odin — do not edit by hand.\n")
	strings.write_string(&b, "// regenerate with: odin run . -- bridge\n")
	strings.write_string(&b, "package bridge\n\nforeign import lib \"../../build/desktop/libbridge.a\"\n_ :: lib\n\n@(default_calling_convention=\"c\")\nforeign lib {\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		ps := make([dynamic]string)
		for p in f.params {
			append(&ps, fmt.tprintf("%s: %s", p.name, p.typ))
		}
		if f.ret == "" {
			strings.write_string(&b, fmt.tprintf("\t%s :: proc(%s) ---\n", f.name, strings.join(ps[:], ", ")))
		} else {
			strings.write_string(&b, fmt.tprintf("\t%s :: proc(%s) -> %s ---\n", f.name, strings.join(ps[:], ", "), f.ret))
		}
	}
	strings.write_string(&b, "}\n")
	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

emit_kotlin :: proc(path, package_name, class_name: string, funcs: [dynamic]Func) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, fmt.tprintf("package %s\n\n", package_name))
	strings.write_string(&b, "// generated by bridgegen from app/bridge.odin — do not edit by hand.\n")
	strings.write_string(&b, "// regenerate with: odin run . -- bridge\n\n")
	strings.write_string(&b, fmt.tprintf("object %s ", class_name))
	strings.write_string(&b, "{\n")
	strings.write_string(&b, "    // set by the host activity before any bridge call\n")
	strings.write_string(&b, "    @JvmStatic lateinit var activity: android.app.Activity\n\n")

	strings.write_string(&b, "    // ---- kotlin -> odin (exports) ----\n")
	for f in funcs {
		if !f.is_export {
			continue
		}
		kname := camel(f.name)
		ps := make([dynamic]string)
		for p in f.params {
			append(&ps, fmt.tprintf("%s: %s", p.name, kotlin_type(p.typ)))
		}
		if f.ret == "" {
			strings.write_string(&b, fmt.tprintf("    @JvmStatic external fun %s(%s)\n\n", kname, strings.join(ps[:], ", ")))
		} else {
			strings.write_string(&b, fmt.tprintf("    @JvmStatic external fun %s(%s): %s\n\n", kname, strings.join(ps[:], ", "), kotlin_type(f.ret)))
		}
	}

	strings.write_string(&b, "    // ---- odin -> platform (called through JNI from libmain) ----\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		if f.ret != "" {
			fail(fmt.tprintf("import %s must not return a value in phase 1", f.name))
		}
		kname := camel(f.name)
		ps := make([dynamic]string)
		args := make([dynamic]string)
		for p in f.params {
			append(&ps, fmt.tprintf("%s: %s", p.name, kotlin_type(p.typ)))
			append(&args, fmt.tprintf("%s as Any", p.name))
		}
		strings.write_string(&b, fmt.tprintf("    @JvmStatic fun %s(%s)", kname, strings.join(ps[:], ", ")))
		strings.write_string(&b, " {\n")
		strings.write_string(&b, "        activity.runOnUiThread {\n")
		strings.write_string(&b, fmt.tprintf("            onPlatformEvent(\"%s\", listOf(%s))\n", kname, strings.join(args[:], ", ")))
		strings.write_string(&b, "        }\n")
		strings.write_string(&b, "    }\n\n")
	}

	strings.write_string(&b, "    @JvmStatic fun onPlatformEvent(name: String, args: List<Any>) {\n")
	strings.write_string(&b, "        when (name) {\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		strings.write_string(&b, fmt.tprintf("            \"%s\" -> android.widget.Toast.makeText(activity, args.filterIsInstance<String>().joinToString(), android.widget.Toast.LENGTH_SHORT).show()\n", camel(f.name)))
	}
	strings.write_string(&b, "        }\n")
	strings.write_string(&b, "    }\n")
	strings.write_string(&b, "}\n")
	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

emit_jni :: proc(path, package_name, class_name: string, funcs: [dynamic]Func) {
	pkg_u, _ := strings.replace(package_name, ".", "_", -1)
	b: strings.Builder
	strings.builder_init(&b)

	strings.write_string(&b, "// generated by bridgegen from app/bridge.odin — do not edit by hand.\n")
	strings.write_string(&b, "#include <jni.h>\n#include <string.h>\n#include \"bridge.h\"\n\n")
	strings.write_string(&b, "static JavaVM *g_jvm;\nstatic jclass g_class;\n")

	strings.write_string(&b, "// ---- odin -> platform: cached method ids ----\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		strings.write_string(&b, fmt.tprintf("static jmethodID g_mid_%s;\n", camel(f.name)))
	}
	strings.write_string(&b, "\nJNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {\n")
	strings.write_string(&b, "    (void)reserved;\n    g_jvm = vm;\n    JNIEnv *env = 0;\n")
	strings.write_string(&b, "    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;\n")
	strings.write_string(&b, fmt.tprintf("    jclass local = (*env)->FindClass(env, \"%s/%s\");\n", package_name, class_name))
	strings.write_string(&b, "    if (!local) return JNI_ERR;\n")
	strings.write_string(&b, "    g_class = (*env)->NewGlobalRef(env, local);\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		param_sigs := make([dynamic]string)
		for p in f.params {
			append(&param_sigs, jni_sig(p.typ))
		}
		ret_sig := jni_sig(f.ret)
		kname := camel(f.name)
		strings.write_string(&b, fmt.tprintf("    g_mid_%s = (*env)->GetStaticMethodID(env, g_class, \"%s\", \"(%s)%s\");\n", kname, kname, strings.join(param_sigs[:], ""), ret_sig))
		strings.write_string(&b, fmt.tprintf("    if (!g_mid_%s) return JNI_ERR;\n", kname))
	}
	strings.write_string(&b, "    (*env)->DeleteLocalRef(env, local);\n    return JNI_VERSION_1_6;\n}\n\n")

	strings.write_string(&b, "static JNIEnv *bridge_env(void) {\n")
	strings.write_string(&b, "    JNIEnv *env = 0;\n    jint state = (*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6);\n")
	strings.write_string(&b, "    if (state == JNI_EDETACHED) (*g_jvm)->AttachCurrentThread(g_jvm, &env, 0);\n")
	strings.write_string(&b, "    return env;\n}\n\n")

	strings.write_string(&b, "// ---- kotlin -> odin: export wrappers ----\n")
	for f in funcs {
		if !f.is_export {
			continue
		}
		kname := camel(f.name)
		jni_params := make([dynamic]string)
		call_args := make([dynamic]string)
		prelude := make([dynamic]string)
		epilogue := make([dynamic]string)
		for p in f.params {
			append(&jni_params, fmt.tprintf("%s %s", jni_type(p.typ), p.name))
			if p.typ == "cstring" {
				append(&prelude, fmt.tprintf("    const char *p_%s = (*env)->GetStringUTFChars(env, %s, 0);\n", p.name, p.name))
				append(&call_args, fmt.tprintf("p_%s", p.name))
				append(&epilogue, fmt.tprintf("    (*env)->ReleaseStringUTFChars(env, %s, p_%s);\n", p.name, p.name))
			} else {
				append(&call_args, p.name)
			}
		}
		strings.write_string(&b, fmt.tprintf("JNIEXPORT %s JNICALL Java_%s_%s_%s(JNIEnv *env, jclass clazz", jni_type(f.ret), pkg_u, class_name, kname))
		if len(jni_params) > 0 {
			strings.write_string(&b, fmt.tprintf(", %s", strings.join(jni_params[:], ", ")))
		}
		strings.write_string(&b, ") {\n    (void)clazz;\n")
		for l in prelude {
			strings.write_string(&b, l)
		}
		call := fmt.tprintf("%s(%s)", f.name, strings.join(call_args[:], ", "))
		if f.ret == "" {
			strings.write_string(&b, fmt.tprintf("    %s;\n", call))
		} else if f.ret == "cstring" {
			strings.write_string(&b, fmt.tprintf("    return (*env)->NewStringUTF(env, %s);\n", call))
		} else {
			strings.write_string(&b, fmt.tprintf("    return %s;\n", call))
		}
		for l in epilogue {
			strings.write_string(&b, l)
		}
		strings.write_string(&b, "}\n\n")
	}

	strings.write_string(&b, "// ---- odin -> platform: jni up-calls ----\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		kname := camel(f.name)
		c_params := make([dynamic]string)
		for p in f.params {
			append(&c_params, fmt.tprintf("%s %s", c_type(p.typ), p.name))
		}
		strings.write_string(&b, fmt.tprintf("void %s(", f.name))
		if len(c_params) > 0 {
			strings.write_string(&b, strings.join(c_params[:], ", "))
		} else {
			strings.write_string(&b, "void")
		}
		strings.write_string(&b, ") {\n")
		strings.write_string(&b, "    JNIEnv *env = bridge_env();\n")
		strings.write_string(&b, fmt.tprintf("    if (!env || !g_mid_%s) return;\n", kname))
		call_args := make([dynamic]string)
		locals := make([dynamic]string)
		for p, idx in f.params {
			if p.typ == "cstring" {
				strings.write_string(&b, fmt.tprintf("    jstring jarg%d = (*env)->NewStringUTF(env, %s);\n", idx, p.name))
				append(&call_args, fmt.tprintf("jarg%d", idx))
				append(&locals, fmt.tprintf("    (*env)->DeleteLocalRef(env, jarg%d);\n", idx))
			} else {
				append(&call_args, p.name)
			}
		}
		param_sigs := make([dynamic]string)
		for p in f.params {
			append(&param_sigs, jni_sig(p.typ))
		}
		strings.write_string(&b, fmt.tprintf("    (*env)->CallStaticVoidMethod(env, g_class, g_mid_%s", kname))
		if len(call_args) > 0 {
			strings.write_string(&b, fmt.tprintf(", %s", strings.join(call_args[:], ", ")))
		}
		strings.write_string(&b, ");\n")
		for l in locals {
			strings.write_string(&b, l)
		}
		strings.write_string(&b, "}\n\n")
	}

	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

main :: proc() {
	args := os.args
	source, hdr_out, odin_out, kt_out, jni_out, package_name, class_name := "", "", "", "", "", "", ""
	i := 1
	for i < len(args) {
		a := args[i]
		if a == "--source" && i + 1 < len(args) {
			i += 1
			source = args[i]
		} else if a == "--hdr" && i + 1 < len(args) {
			i += 1
			hdr_out = args[i]
		} else if a == "--odin" && i + 1 < len(args) {
			i += 1
			odin_out = args[i]
		} else if a == "--kt" && i + 1 < len(args) {
			i += 1
			kt_out = args[i]
		} else if a == "--jni" && i + 1 < len(args) {
			i += 1
			jni_out = args[i]
		} else if a == "--package" && i + 1 < len(args) {
			i += 1
			package_name = args[i]
		} else if a == "--class" && i + 1 < len(args) {
			i += 1
			class_name = args[i]
		} else {
			fail(fmt.tprintf("unknown argument: %s", a))
		}
		i += 1
	}
	if source == "" || hdr_out == "" || odin_out == "" || kt_out == "" || jni_out == "" || package_name == "" || class_name == "" {
		fmt.println("usage: bridgegen --source <bridge.odin> --hdr <bridge.h> --odin <bridge.odin.out> --kt <OdinBridge.kt> --jni <bridge_jni.c> --package <java.package> --class <ClassName>")
		os.exit(1)
	}

	funcs := parse_source(source)
	sh(fmt.tprintf("mkdir -p '%s'", jp(filepath.dir(jni_out))))
	emit_header(hdr_out, funcs)
	emit_odin(odin_out, funcs)
	emit_kotlin(kt_out, package_name, class_name, funcs)
	emit_jni(jni_out, package_name, class_name, funcs)
}
