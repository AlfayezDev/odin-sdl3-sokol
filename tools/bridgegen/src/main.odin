package bridgegen

// bridgegen: the single binding generator. Reads the plain-text contract
// (binding/api/bridge.spec) and emits every artifact:
//
//   --hdr <bridge.h>     C header (consumed by Swift bridging, JNI glue, desktop stub)
//   --odin <bridge.odin> Odin foreign procs (odin -> platform imports)
//   --kt  <OdinBridge.kt> Kotlin bridge object
//   --jni  <bridge_jni.c> JNI_OnLoad + Java_<class>_<method> wrappers + up-calls
//
// Direction is encoded in the name prefix:
//   odin_*     implemented in Odin via @(export); Kotlin gets external funs,
//              platforms call the C symbol directly.
//   platform_* implemented by the platform; Odin calls them through the
//              foreign block; Android up-calls into Kotlin.
//
// spec types: string, int, bool, float, double, int64
// spec format (one per line, '#' comments):
//   package <java.package>
//   class   <ClassName>
//   fn name(param: type, ...) -> type        (ret optional, defaults void)
//
// usage:
//   bridgegen --spec binding/api/bridge.spec --hdr binding/api/bridge.h \
//             --odin vendors/bridge/bridge.odin \
//             --kt binding/android/java/dev/alfayez/odinsokol/OdinBridge.kt \
//             --jni build/gen/bridge_jni.c

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
	typ:  string, // spec name: "string" "int" "bool" "float" "double" "int64"
}

Func :: struct {
	name:      string,
	ret:       string,
	params:    [dynamic]Param,
	is_export: bool, // odin_ prefix
}

Spec :: struct {
	package_name: string,
	class_name:   string,
	funcs:        [dynamic]Func,
}

// ---- type maps: spec name -> per-language spelling ----

c_type :: proc(t: string) -> string {
	if t == "string" {
		return "const char *"
	}
	if t == "int" {
		return "int32_t"
	}
	if t == "int64" {
		return "int64_t"
	}
	if t == "bool" {
		return "bool"
	}
	if t == "float" {
		return "float"
	}
	if t == "double" {
		return "double"
	}
	if t == "void" {
		return "void"
	}
	return ""
}

kotlin_type :: proc(t: string) -> string {
	if t == "string" {
		return "String"
	}
	if t == "int" {
		return "Int"
	}
	if t == "int64" {
		return "Long"
	}
	if t == "bool" {
		return "Boolean"
	}
	if t == "float" {
		return "Float"
	}
	if t == "double" {
		return "Double"
	}
	return t
}

jni_type :: proc(t: string) -> string {
	if t == "string" {
		return "jstring"
	}
	if t == "int" {
		return "jint"
	}
	if t == "int64" {
		return "jlong"
	}
	if t == "bool" {
		return "jboolean"
	}
	if t == "float" {
		return "jfloat"
	}
	if t == "double" {
		return "jdouble"
	}
	return "void"
}

jni_sig :: proc(t: string) -> string {
	if t == "string" {
		return "Ljava/lang/String;"
	}
	if t == "int" {
		return "I"
	}
	if t == "int64" {
		return "J"
	}
	if t == "bool" {
		return "Z"
	}
	if t == "float" {
		return "F"
	}
	if t == "double" {
		return "D"
	}
	return "V"
}

odin_type :: proc(t: string) -> string {
	if t == "string" {
		return "cstring"
	}
	if t == "int" {
		return "i32"
	}
	if t == "int64" {
		return "i64"
	}
	if t == "bool" {
		return "b32"
	}
	if t == "float" {
		return "f32"
	}
	if t == "double" {
		return "f64"
	}
	return t
}

check_type :: proc(t: string, site: string) {
	ok := t == "void" || t == "string" || t == "int" || t == "bool" || t == "float" || t == "double" || t == "int64"
	if !ok {
		fail(fmt.tprintf("unknown type '%s' (%s) — spec types: string, int, int64, bool, float, double (+ implicit void returns)", t, site))
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

// ---- spec parsing ----

parse_spec :: proc(path: string) -> Spec {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fail(fmt.tprintf("cannot read spec %s", path))
	}
	s := Spec{funcs = make([dynamic]Func)}
	for line in strings.split(string(data), "\n") {
		l := strings.trim_space(line)
		if len(l) == 0 || l[0] == '#' {
			continue
		}
		if strings.has_prefix(l, "package ") {
			s.package_name = strings.trim_space(l[len("package"):])
			continue
		}
		if strings.has_prefix(l, "class ") {
			s.class_name = strings.trim_space(l[len("class"):])
			continue
		}
		if !strings.has_prefix(l, "fn ") {
			continue
		}
		rest := strings.trim_space(l[3:])
		ret := "void"
		if arrow := strings.index_byte(rest, '>'); arrow >= 0 {
			// find the "-> " separator: scan for '-' followed by '>'
			arrow_idx := -1
			for i := 0; i < len(rest) - 1; i += 1 {
				if rest[i] == '-' && rest[i + 1] == '>' {
					arrow_idx = i
					break
				}
			}
			if arrow_idx < 0 {
				fail(fmt.tprintf("bad fn line: %s", l))
			}
			ret = strings.trim_space(rest[arrow_idx + 2:])
			rest = strings.trim_space(rest[:arrow_idx])
		}
		open := strings.index_byte(rest, '(')
		close := strings.last_index_byte(rest, ')')
		if open < 0 || close < open || close != len(rest) - 1 {
			fail(fmt.tprintf("bad fn line: %s", l))
		}
		name := strings.trim_space(rest[:open])
		if !strings.has_prefix(name, "odin_") && !strings.has_prefix(name, "platform_") {
			fail(fmt.tprintf("fn name must start with odin_ or platform_: %s", name))
		}
		check_type(ret, fmt.tprintf("%s return", name))

		f := Func{name = name, ret = ret, is_export = strings.has_prefix(name, "odin_"), params = make([dynamic]Param)}
		inner := strings.trim_space(rest[open + 1:close])
		if len(inner) > 0 && inner != "void" {
			for p in strings.split(inner, ",") {
				colon := strings.index_byte(p, ':')
				if colon < 0 {
					fail(fmt.tprintf("param needs 'name: type': '%s' in %s", strings.trim_space(p), name))
				}
				pname := strings.trim_space(p[:colon])
				ptype := strings.trim_space(p[colon + 1:])
				check_type(ptype, fmt.tprintf("%s(%s)", name, pname))
				append(&f.params, Param{pname, ptype})
			}
		}
		append(&s.funcs, f)
	}
	exports, imports := 0, 0
	for f in s.funcs {
		if f.is_export {
			exports += 1
		} else {
			imports += 1
		}
	}
	if s.package_name == "" || s.class_name == "" || exports + imports == 0 {
		fail("spec needs 'package', 'class' and at least one fn")
	}
	fmt.println("bridgegen: parsed", exports, "export(s),", imports, "import(s)")
	return s
}

// ---- emitters ----

// C header: the ABI contract consumed by Swift (bridging header), the JNI
// glue and the desktop stub. Committed: stable, reviewable, tiny.
emit_header :: proc(path: string, spec: Spec) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "/* generated by bridgegen from binding/api/bridge.spec — do not edit by hand.\n")
	strings.write_string(&b, "   the spec is the source of truth; regenerate with: odin run . -- bridge */\n")
	strings.write_string(&b, "#ifndef BRIDGE_H\n#define BRIDGE_H\n\n#include <stdint.h>\n#include <stdbool.h>\n\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n")
	strings.write_string(&b, "/* platform -> odin */\n")
	for f in spec.funcs {
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
	strings.write_string(&b, "/* odin -> platform */\n")
	for f in spec.funcs {
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

// Odin foreign block: only the platform_* half (odin_* are real @(export)
// procs in app/bridge.odin — declaring them foreign would be a clash).
// The foreign import points at the desktop-linked archive; android/ios
// build in obj mode where it is inert.
emit_odin :: proc(path: string, spec: Spec) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "// generated by bridgegen from binding/api/bridge.spec — do not edit by hand.\n")
	strings.write_string(&b, "// regenerate with: odin run . -- bridge\n")
	strings.write_string(&b, "package bridge\n\nforeign import lib \"../../build/desktop/libbridge.a\"\n_ :: lib\n\n@(default_calling_convention=\"c\")\nforeign lib {\n")
	for f in spec.funcs {
		if f.is_export {
			continue
		}
		ps := make([dynamic]string)
		for p in f.params {
			append(&ps, fmt.tprintf("%s: %s", p.name, odin_type(p.typ)))
		}
		if f.ret == "void" {
			strings.write_string(&b, fmt.tprintf("\t%s :: proc(%s) ---\n", f.name, strings.join(ps[:], ", ")))
		} else {
			strings.write_string(&b, fmt.tprintf("\t%s :: proc(%s) -> %s ---\n", f.name, strings.join(ps[:], ", "), odin_type(f.ret)))
		}
	}
	strings.write_string(&b, "}\n")
	_ = os.write_entire_file_from_string(path, strings.to_string(b))
	fmt.println("bridgegen: wrote", path)
}

// Kotlin bridge object: external funs for exports, dispatcher funs for imports.
emit_kotlin :: proc(path: string, spec: Spec) {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, fmt.tprintf("package %s\n\n", spec.package_name))
	strings.write_string(&b, "// generated by bridgegen from binding/api/bridge.spec — do not edit by hand.\n")
	strings.write_string(&b, "// regenerate with: odin run . -- bridge\n\n")
	strings.write_string(&b, fmt.tprintf("object %s ", spec.class_name))
	strings.write_string(&b, "{\n")
	strings.write_string(&b, "    // set by the host activity before any bridge call\n")
	strings.write_string(&b, "    @JvmStatic lateinit var activity: android.app.Activity\n\n")

	strings.write_string(&b, "    // ---- kotlin -> odin (exports) ----\n")
	for f in spec.funcs {
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
	for f in spec.funcs {
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
	for f in spec.funcs {
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

// JNI glue: JNI_OnLoad (caches JavaVM + class + method ids), Java_<class>_<method>
// wrappers for exports, C implementations of platform_* with up-calls.
emit_jni :: proc(path: string, spec: Spec) {
	pkg_u, _ := strings.replace(spec.package_name, ".", "_", -1)
	b: strings.Builder
	strings.builder_init(&b)

	strings.write_string(&b, "// generated by bridgegen from binding/api/bridge.spec — do not edit by hand.\n")
	strings.write_string(&b, "#include <jni.h>\n#include <string.h>\n#include \"bridge.h\"\n\n")
	strings.write_string(&b, "static JavaVM *g_jvm;\nstatic jclass g_class;\n")

	strings.write_string(&b, "// ---- odin -> platform: cached method ids ----\n")
	for f in spec.funcs {
		if f.is_export {
			continue
		}
		strings.write_string(&b, fmt.tprintf("static jmethodID g_mid_%s;\n", camel(f.name[9:])))
	}
	strings.write_string(&b, "\nJNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {\n")
	strings.write_string(&b, "    (void)reserved;\n    g_jvm = vm;\n    JNIEnv *env = 0;\n")
	strings.write_string(&b, "    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;\n")
	strings.write_string(&b, fmt.tprintf("    jclass local = (*env)->FindClass(env, \"%s/%s\");\n", spec.package_name, spec.class_name))
	strings.write_string(&b, "    if (!local) return JNI_ERR;\n")
	strings.write_string(&b, "    g_class = (*env)->NewGlobalRef(env, local);\n")
	for f in spec.funcs {
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

	strings.write_string(&b, "// ---- kotlin -> odin: export wrappers ----\n")
	for f in spec.funcs {
		if !f.is_export {
			continue
		}
		kname := camel(f.name[5:])
		jni_params := make([dynamic]string)
		call_args := make([dynamic]string)
		prelude := make([dynamic]string)
		epilogue := make([dynamic]string)
		for p in f.params {
			append(&jni_params, fmt.tprintf("%s %s", jni_type(p.typ), p.name))
			if p.typ == "string" {
				append(&prelude, fmt.tprintf("    const char *p_%s = (*env)->GetStringUTFChars(env, %s, 0);\n", p.name, p.name))
				append(&call_args, fmt.tprintf("p_%s", p.name))
				append(&epilogue, fmt.tprintf("    (*env)->ReleaseStringUTFChars(env, %s, p_%s);\n", p.name, p.name))
			} else {
				append(&call_args, p.name)
			}
		}
		strings.write_string(&b, fmt.tprintf("JNIEXPORT %s JNICALL Java_%s_%s_%s(JNIEnv *env, jclass clazz", jni_type(f.ret), pkg_u, spec.class_name, kname))
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
		} else if f.ret == "string" {
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
	for f in spec.funcs {
		if f.is_export {
			continue
		}
		kname := camel(f.name[9:])
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
			if p.typ == "string" {
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

// parity check: every odin_* in the spec should have a matching @(export)
// proc somewhere in app/*.odin (text-level scan — catches silent breaks).
parity_check :: proc(spec_dir, app_dir: string, spec: Spec) {
	for f in spec.funcs {
		if !f.is_export {
			continue
		}
		found := false
		entries, err := os.read_directory_by_path(app_dir, -1, context.temp_allocator)
		if err != nil {
			continue
		}
		for e in entries {
			if !strings.has_suffix(e.name, ".odin") {
				continue
			}
			data, rerr := os.read_entire_file_from_path(jp(app_dir, e.name), context.temp_allocator)
			if rerr != nil {
				continue
			}
			if strings.contains(string(data), fmt.tprintf("%s :: proc", f.name)) {
				found = true
				break
			}
		}
		if !found {
			fail(fmt.tprintf("parity: spec declares '%s' but no proc '%s :: proc' found in %s (missing @(export) implementation?)", f.name, f.name, app_dir))
		}
	}
	fmt.println("bridgegen: parity ok — all odin_* exports implemented in app/")
}

main :: proc() {
	args := os.args
	spec_file, hdr_out, odin_out, kt_out, jni_out := "", "", "", "", ""
	i := 1
	for i < len(args) {
		a := args[i]
		if a == "--spec" && i + 1 < len(args) {
			i += 1
			spec_file = args[i]
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
		} else {
			fail(fmt.tprintf("unknown argument: %s", a))
		}
		i += 1
	}
	if spec_file == "" || hdr_out == "" || odin_out == "" || kt_out == "" || jni_out == "" {
		fmt.println("usage: bridgegen --spec <bridge.spec> --hdr <bridge.h> --odin <bridge.odin> --kt <OdinBridge.kt> --jni <bridge_jni.c>")
		os.exit(1)
	}

	spec := parse_spec(spec_file)
	parity_check(jp(filepath.dir(spec_file), "../.."), "app", spec)
	sh(fmt.tprintf("mkdir -p '%s'", jp(filepath.dir(jni_out))))
	emit_header(hdr_out, spec)
	emit_odin(odin_out, spec)
	emit_kotlin(kt_out, spec)
	emit_jni(jni_out, spec)
}
