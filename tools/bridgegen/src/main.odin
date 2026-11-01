package bridgegen

// bridgegen: reads the constrained C contract (binding/api/bridge.h) and
// generates the Kotlin bridge object + the JNI glue C file for Android.
//
//   odin_*     exports -> Kotlin `external fun` + Java_<class>_<method>
//                C wrappers that call the Odin export.
//   platform_* imports -> C implementations that up-call into Kotlin
//                through cached jclass/jmethodID (attached threads).
//
// Supported types: void, bool, int32_t, float, const char*.
// Prototypes must be single-line and end with ");".
//
// usage:
//   bridgegen --header binding/api/bridge.h \
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
	typ:  string, // canonical: "void" "bool" "int32_t" "float" "const char*"
}

Func :: struct {
	name:      string,
	ret:       string,
	params:    [dynamic]Param,
	is_export: bool, // odin_ prefix
}

canonical_type :: proc(t: string) -> string {
	c, _ := strings.replace(t, " ", "", -1)
	out, _ := strings.replace(c, "*", "", -1)
	return out
}

is_ptr :: proc(t: string) -> bool {
	return strings.contains(t, "*")
}

check_type :: proc(t: string, site: string) {
	c := canonical_type(t)
	if is_ptr(t) {
		if c != "constchar" {
			fail(fmt.tprintf("unsupported pointer type '%s' (%s) — whitelist: const char*", t, site))
		}
		return
	}
	if c != "void" && c != "bool" && c != "int32_t" && c != "float" {
		fail(fmt.tprintf("unsupported type '%s' (%s) — whitelist: void, bool, int32_t, float, const char*", t, site))
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
		if up >= 'a' && up <= 'z' do up -= 'a' - 'A'
		out = fmt.tprintf("%s%c%s", out, rune(up), p[1:])
	}
	return out
}

parse_prototype :: proc(line_in: string) -> (f: Func, ok: bool) {
	line := strings.trim_space(line_in)
	if !strings.contains(line, "(") || !strings.has_suffix(line, ");") {
		return
	}
	open := strings.index_byte(line, '(')
	close := strings.last_index_byte(line, ')')
	if open < 0 || close < open {
		return
	}
	left := strings.trim_space(line[:open])
	inner := strings.trim_space(line[open + 1:close])

	toks := make([dynamic]string)
	for tok in strings.split(left, " ") {
		t := strings.trim_space(tok)
		if len(t) > 0 {
			append(&toks, t)
		}
	}
	if len(toks) < 2 {
		return
	}
	name_tok := toks[len(toks) - 1]
	name := strings.trim_space(strings.trim_left(name_tok, "*"))
	if !strings.has_prefix(name, "odin_") && !strings.has_prefix(name, "platform_") {
		return
	}
	star := name_tok != name
	ret := strings.join(toks[:len(toks) - 1], " ")
	if star {
		ret = fmt.tprintf("%s *", ret)
	}
	check_type(ret, fmt.tprintf("%s return", name))

	f.name = name
	f.ret = ret
	f.is_export = strings.has_prefix(name, "odin_")
	f.params = make([dynamic]Param)

	if inner == "void" {
		return f, true
	}
	if len(inner) > 0 {
		for p in strings.split(inner, ",") {
			ptoks := make([dynamic]string)
			for tok in strings.split(strings.trim_space(p), " ") {
				pt := strings.trim_space(tok)
				if len(pt) > 0 {
					append(&ptoks, pt)
				}
			}
			if len(ptoks) < 2 {
				fail(fmt.tprintf("cannot parse param '%s' of %s", p, name))
			}
			pname_tok := ptoks[len(ptoks) - 1]
			pname := strings.trim_space(strings.trim_left(pname_tok, "*"))
			pstar := pname_tok != pname
			ptype := strings.join(ptoks[:len(ptoks) - 1], " ")
			if pstar {
				ptype = fmt.tprintf("%s *", ptype)
			}
			check_type(ptype, fmt.tprintf("%s(%s)", name, pname))
			append(&f.params, Param{pname, ptype})
		}
	}
	return f, true
}

parse_header :: proc(path: string) -> [dynamic]Func {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fail(fmt.tprintf("cannot read header %s", path))
	}
	funcs := make([dynamic]Func)
	for line in strings.split(string(data), "\n") {
		s := strings.trim_space(line)
		if len(s) == 0 || s[0] == '/' || s[0] == '*' || s[0] == '#' {
			continue
		}
		if f, ok := parse_prototype(s); ok {
			append(&funcs, f)
		}
	}
	exports, imports := 0, 0
	for f in funcs {
		if f.is_export {
			exports += 1
		} else {
			imports += 1
		}
	}
	if exports + imports == 0 {
		fail("no odin_*/platform_* prototypes found in header")
	}
	fmt.println("bridgegen: parsed", exports, "export(s),", imports, "import(s)")
	return funcs
}

// ---- type maps ----

kotlin_type :: proc(t: string) -> string {
	c := canonical_type(t)
	if is_ptr(t) && c == "constchar" {
		return "String"
	}
	if c == "bool" {
		return "Boolean"
	}
	if c == "int32_t" {
		return "Int"
	}
	if c == "float" {
		return "Float"
	}
	return c
}

jni_type :: proc(t: string) -> string {
	c := canonical_type(t)
	if is_ptr(t) && c == "constchar" {
		return "jstring"
	}
	if c == "bool" {
		return "jboolean"
	}
	if c == "int32_t" {
		return "jint"
	}
	if c == "float" {
		return "jfloat"
	}
	return "void"
}

jni_sig :: proc(t: string) -> string {
	c := canonical_type(t)
	if is_ptr(t) && c == "constchar" {
		return "Ljava/lang/String;"
	}
	if c == "bool" {
		return "Z"
	}
	if c == "int32_t" {
		return "I"
	}
	if c == "float" {
		return "F"
	}
	return "V"
}

// ---- kotlin emission ----

emit_kotlin :: proc(path, package_name, class_name: string, funcs: [dynamic]Func) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, fmt.tprintf("package %s\n\n", package_name))
	strings.write_string(&b, "// generated by bridgegen from binding/api/bridge.h — do not edit by hand.\n")
	strings.write_string(&b, "// regenerate: build/tools/bridgegen --header binding/api/bridge.h --kt <this file> --jni build/gen/bridge_jni.c\n\n")
	strings.write_string(&b, fmt.tprintf("object %s ", class_name))
	strings.write_string(&b, "{\n")
	strings.write_string(&b, "    // set by the host activity before any bridge call\n")
	strings.write_string(&b, "    @JvmStatic lateinit var activity: android.app.Activity\n\n")

	strings.write_string(&b, "    // ---- kotlin -> odin (exports) ----\n")
	for f in funcs {
		if !f.is_export {
			continue
		}
		kname := camel(f.name[5:])
		ps := make([dynamic]string)
		for p in f.params {
			append(&ps, fmt.tprintf("%s: %s", p.name, kotlin_type(p.typ)))
		}
		if f.ret == "void" {
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
		if f.ret != "void" {
			fail(fmt.tprintf("platform_* function %s must return void in phase 1", f.name))
		}
		kname := camel(f.name[9:])
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
		strings.write_string(&b, fmt.tprintf("            \"%s\" -> android.widget.Toast.makeText(activity, args.filterIsInstance<String>().joinToString(), android.widget.Toast.LENGTH_SHORT).show()\n", camel(f.name[9:])))
	}
	strings.write_string(&b, "        }\n")
	strings.write_string(&b, "    }\n")
	strings.write_string(&b, "}\n")
	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

// ---- jni c emission ----

emit_jni :: proc(path, package_name, class_name: string, funcs: [dynamic]Func) {
	pkg_u, _ := strings.replace(package_name, ".", "_", -1)
	b: strings.Builder
	strings.builder_init(&b)

	strings.write_string(&b, "// generated by bridgegen from binding/api/bridge.h — do not edit by hand.\n")
	strings.write_string(&b, "#include <jni.h>\n#include <string.h>\n#include \"bridge.h\"\n\n")
	strings.write_string(&b, "static JavaVM *g_jvm;\nstatic jclass g_class;\n")

	// method-id cache for up-calls
	strings.write_string(&b, "// ---- odin -> platform: cached method ids ----\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		strings.write_string(&b, fmt.tprintf("static jmethodID g_mid_%s;\n", camel(f.name[9:])))
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
		kname := camel(f.name[9:])
		strings.write_string(&b, fmt.tprintf("    g_mid_%s = (*env)->GetStaticMethodID(env, g_class, \"%s\", \"(%s)%s\");\n", kname, kname, strings.join(param_sigs[:], ""), ret_sig))
		strings.write_string(&b, fmt.tprintf("    if (!g_mid_%s) return JNI_ERR;\n", kname))
	}
	strings.write_string(&b, "    (*env)->DeleteLocalRef(env, local);\n    return JNI_VERSION_1_6;\n}\n\n")

	strings.write_string(&b, "static JNIEnv *bridge_env(void) {\n")
	strings.write_string(&b, "    JNIEnv *env = 0;\n    jint state = (*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6);\n")
	strings.write_string(&b, "    if (state == JNI_EDETACHED) (*g_jvm)->AttachCurrentThread(g_jvm, &env, 0);\n")
	strings.write_string(&b, "    return env;\n}\n\n")

	// kotlin -> odin wrappers
	strings.write_string(&b, "// ---- kotlin -> odin: export wrappers ----\n")
	for f in funcs {
		if !f.is_export {
			continue
		}
		kname := camel(f.name[5:])
		jni_params := make([dynamic]string)
		call_args := make([dynamic]string)
		prelude := make([dynamic]string)
		epilogue := make([dynamic]string)
		for p, idx in f.params {
			append(&jni_params, fmt.tprintf("%s %s", jni_type(p.typ), p.name))
			c := canonical_type(p.typ)
			if is_ptr(p.typ) {
				append(&prelude, fmt.tprintf("    const char *p_%s = (*env)->GetStringUTFChars(env, %s, 0);\n", p.name, p.name))
				append(&call_args, fmt.tprintf("p_%s", p.name))
				append(&epilogue, fmt.tprintf("    (*env)->ReleaseStringUTFChars(env, %s, p_%s);\n", p.name, p.name))
			} else {
				append(&call_args, p.name)
			}
			_ = idx
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
		if f.ret == "void" {
			strings.write_string(&b, fmt.tprintf("    %s;\n", call))
		} else if is_ptr(f.ret) {
			strings.write_string(&b, fmt.tprintf("    return (*env)->NewStringUTF(env, %s);\n", call))
		} else {
			strings.write_string(&b, fmt.tprintf("    return %s;\n", call))
		}
		for l in epilogue {
			strings.write_string(&b, l)
		}
		strings.write_string(&b, "}\n\n")
	}

	// odin -> platform up-calls
	strings.write_string(&b, "// ---- odin -> platform: jni up-calls ----\n")
	for f in funcs {
		if f.is_export {
			continue
		}
		kname := camel(f.name[9:])
		c_params := make([dynamic]string)
		for p in f.params {
			append(&c_params, fmt.tprintf("%s %s", p.typ, p.name))
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
			j := jni_type(p.typ)
			if j == "jstring" {
				strings.write_string(&b, fmt.tprintf("    jstring jarg%d = (*env)->NewStringUTF(env, %s);\n", idx, p.name))
				append(&call_args, fmt.tprintf("jarg%d", idx))
				append(&locals, fmt.tprintf("    (*env)->DeleteLocalRef(env, jarg%d);\n", idx))
			} else {
				append(&call_args, p.name)
			}
		}
		sigs := make([dynamic]string)
		for p in f.params {
			append(&sigs, jni_sig(p.typ))
		}
		append(&sigs, jni_sig(f.ret))
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
	header, kt_out, jni_out, package_name, class_name := "", "", "", "", ""
	i := 1
	for i < len(args) {
		a := args[i]
		if a == "--header" && i + 1 < len(args) {
			i += 1
			header = args[i]
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
	if header == "" || kt_out == "" || jni_out == "" || package_name == "" || class_name == "" {
		fmt.println("usage: bridgegen --header <bridge.h> --kt <OdinBridge.kt> --jni <bridge_jni.c> --package <java.package> --class <ClassName>")
		os.exit(1)
	}

	funcs := parse_header(header)
	sh(fmt.tprintf("mkdir -p '%s'", jp(filepath.dir(jni_out))))
	emit_kotlin(kt_out, package_name, class_name, funcs)
	emit_jni(jni_out, package_name, class_name, funcs)
}
