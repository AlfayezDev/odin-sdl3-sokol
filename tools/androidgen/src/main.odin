package androidgen

// androidgen: generate a complete gradle Android project from a small
// declarative spec — the "XcodeGen for Android". Hand-written glue
// (manifest, res, java) stays where it lives; generated files and
// symlinks land in the output project directory.

import "core:c"

foreign {
	system :: proc "c" (command: cstring) -> c.int ---
}
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

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
	fmt.eprintln("androidgen:", msg)
	os.exit(1)
}

usage :: proc() {
	fmt.println("usage: androidgen generate --spec <project.yaml> [--out <dir>] [--templates <asset_dir>]")
	fmt.println("  spec paths are resolved relative to the spec file's directory")
	fmt.println("  output project dir is fully regenerable; add it to .gitignore")
	os.exit(1)
}

// spec: flat "key: value" lines, '#' comments. Repeatable keys: abi, java.
parse_spec :: proc(path: string) -> map[string][dynamic]string {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fail(fmt.tprintf("cannot read spec %s", path))
	}
	m := make(map[string][dynamic]string)
	for line in strings.split(string(data), "\n") {
		s := strings.trim_space(line)
		if len(s) == 0 || s[0] == '#' {
			continue
		}
		colon := -1
		for i in 0..<len(s) {
			if s[i] == ':' {
				colon = i
				break
			}
		}
		if colon <= 0 {
			fail(fmt.tprintf("bad spec line: %s", s))
		}
		key := strings.trim_space(s[:colon])
		val := strings.trim_space(s[colon + 1:])
		if hash := strings.index_byte(val, '#'); hash >= 0 {
			val = strings.trim_space(val[:hash])
		}
		_, ok := m[key]
		if !ok {
			m[key] = make([dynamic]string)
		// dynamic array: appended below via &
		}
		append(&m[key], val)
	}
	return m
}

spec_first :: proc(m: map[string][dynamic]string, key: string) -> string {
	if vals, ok := m[key]; ok && len(vals) > 0 {
		return vals[0]
	}
	return ""
}

// resolve a spec path against the spec file's directory
spec_path :: proc(m: map[string][dynamic]string, key: string, spec_dir: string) -> string {
	val := spec_first(m, key)
	if val == "" {
		return ""
	}
	return jp(spec_dir, val)
}

required_keys := [8]string{"app_id", "namespace", "root_project_name", "compile_sdk", "min_sdk", "target_sdk", "agp_version", "gradle_version"}

render :: proc(tmpl: string, m: map[string][dynamic]string) -> string {
	out := tmpl
	for key, vals in m {
		if len(vals) == 0 {
			continue
		}
		needle := fmt.tprintf("%s%s%s", "{{", key, "}}")
		if strings.contains(out, needle) {
			out, _ = strings.replace(out, needle, vals[0], -1)
		}
	}
	return out
}

run_generate :: proc(args: []string) {
	spec_file := ""
	out_dir := "android"
	tool_dir := ""
	i := 0
	for i < len(args) {
		a := args[i]
		if a == "--spec" && i + 1 < len(args) {
			i += 1
			spec_file = args[i]
		} else if a == "--out" && i + 1 < len(args) {
			i += 1
			out_dir = args[i]
		} else if a == "--templates" && i + 1 < len(args) {
			i += 1
			tool_dir = args[i]
		} else {
			fail(fmt.tprintf("unknown argument: %s", a))
		}
		i += 1
	}
	if spec_file == "" {
		usage()
	}
	spec_file = filepath.abs(spec_file) or_else spec_file
	spec_dir := filepath.dir(spec_file)

	// asset dir: contains templates/ and wrapper/ (default: next to the binary)
	if tool_dir == "" {
		bin := filepath.abs(os.args[0]) or_else os.args[0]
		tool_dir = filepath.dir(bin)
	}

	m := parse_spec(spec_file)
	for key in required_keys {
		if spec_first(m, key) == "" {
			fail(fmt.tprintf("spec missing required key: %s", key))
		}
	}
	abis := m["abi"]
	if len(abis) == 0 {
		fail("spec missing key: abi")
	}
	java_dirs := m["java"]
	if len(java_dirs) == 0 {
		fail("spec missing key: java (at least one java source dir)")
	}

	// computed template values
	abi_parts := make([dynamic]string)
	for a in abis {
		append(&abi_parts, fmt.tprintf("'%s'", a))
	}
	m["abi_filters"] = make([dynamic]string)
	append(&m["abi_filters"], fmt.tprintf("abiFilters %s", strings.join(abi_parts[:], ", ")))

	java_dir_names := make([dynamic]string)
	for jd, idx in java_dirs {
		append(&java_dir_names, fmt.tprintf("'src/main/java-src-%d'", idx + 1))
	}
	m["java_srcdirs"] = make([dynamic]string)
	java_srcdirs_str, _ := strings.concatenate([]string{"    sourceSets {\n        main {\n            java { srcDirs = [", strings.join(java_dir_names[:], ", "), "] }\n        }\n    }\n"})
	append(&m["java_srcdirs"], java_srcdirs_str)

	// layout
	sh(fmt.tprintf("mkdir -p '%s' '%s/app/src/main' '%s/gradle/wrapper'", out_dir, out_dir, out_dir))

	// gradle files from templates
	pairs := [4][2]string{
		{"settings.gradle.tmpl", "settings.gradle"},
		{"build.gradle.tmpl", "build.gradle"},
		{"gradle.properties.tmpl", "gradle.properties"},
		{"app.build.gradle.tmpl", "app/build.gradle"},
	}
	for pair in pairs {
		tmpl_path := jp(tool_dir, "templates", pair[0])
		data, err := os.read_entire_file_from_path(tmpl_path, context.allocator)
		if err != nil {
			fail(fmt.tprintf("missing template: %s", tmpl_path))
		}
		txt := render(string(data), m)
		_ = os.write_entire_file_from_string(jp(out_dir, pair[1]), txt)
	}

	// gradle wrapper: copy scripts + jar, render properties with the spec's version
	sh(fmt.tprintf("cp '%s/wrapper/gradlew' '%s/gradlew' && cp '%s/wrapper/gradlew.bat' '%s/gradlew.bat'", tool_dir, out_dir, tool_dir, out_dir))
	sh(fmt.tprintf("cp '%s/wrapper/gradle/wrapper/gradle-wrapper.jar' '%s/gradle/wrapper/gradle-wrapper.jar'", tool_dir, out_dir))
	sh(fmt.tprintf("chmod +x '%s/gradlew'", out_dir))
	wrapper_data, werr := os.read_entire_file_from_path(jp(tool_dir, "templates/gradle-wrapper.properties.tmpl"), context.allocator)
	if werr != nil {
		fail("missing template: gradle-wrapper.properties.tmpl")
	}
	sha := spec_first(m, "gradle_sha256")
	sha_line := ""
	if sha != "" {
		sha_line = fmt.tprintf("distributionSha256Sum=%s", sha)
	}
	wtxt := render(string(wrapper_data), m)
	wtxt, _ = strings.replace(wtxt, "{{gradle_sha256_line}}", sha_line, -1)
	_ = os.write_entire_file_from_string(jp(out_dir, "gradle/wrapper", "gradle-wrapper.properties"), wtxt)

	// symlink the hand-written glue + external sources into the project
	link :: proc(out_dir, link_rel, target: string) {
		if !sh(fmt.tprintf("test -e '%s'", target)) {
			fail(fmt.tprintf("spec path does not exist: %s", target))
		}
		sh(fmt.tprintf("ln -sfn '%s' '%s'", target, jp(out_dir, link_rel)))
	}
	link(out_dir, "app/src/main/AndroidManifest.xml", spec_path(m, "manifest", spec_dir))
	if res := spec_path(m, "res", spec_dir); res != "" {
		link(out_dir, "app/src/main/res", res)
	}
	for jd, idx in java_dirs {
		link(out_dir, fmt.tprintf("app/src/main/java-src-%d", idx + 1), jp(spec_dir, jd))
	}
	if jni := spec_path(m, "jni_libs", spec_dir); jni != "" {
		link(out_dir, "app/src/main/jniLibs", jni)
	}
	if pg := spec_path(m, "proguard", spec_dir); pg != "" {
		link(out_dir, "app/proguard-rules.pro", pg)
	}

	fmt.println("androidgen: generated", out_dir)
	fmt.println("  gradle files: settings.gradle, build.gradle, app/build.gradle, gradle.properties")
	fmt.println("  wrapper: gradle", spec_first(m, "gradle_version"), "+ agp", spec_first(m, "agp_version"))
	fmt.println("  linked: manifest, res,", len(java_dirs), "java dir(s), jniLibs")
	fmt.println("build with: cd", out_dir, "&& ./gradlew assembleDebug")
}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		usage()
	}
	switch args[1] {
	case "generate":
		run_generate(args[2:])
	case:
		usage()
	}
}
