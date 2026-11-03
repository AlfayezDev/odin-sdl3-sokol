package androidgen

import "core:fmt"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

Target_Kind :: enum {
	Application,
	Library,
	Jvm,
}

Build_Type :: struct {
	name:    string, // normalized Gradle build type name
	display: string, // original config name
	kind:    string, // "debug", "release", or "none"
}

Project_Options :: struct {
	bundle_id_prefix:        string,
	deployment_target:       int,
	setting_presets:         string,
	default_config:          string,
	pre_gen_command:         string,
	post_gen_command:        string,
	output_dir:              string,
	android:                 Android_Options,
	min_androidgen_version:  string,
}

Android_Options :: struct {
	compile_sdk:         int,
	build_tools_version: string,
	ndk_version:         string,
	agp_version:         string,
	gradle_version:      string,
	gradle_sha256:       string,
	kotlin_version:      string,
	output_dir:          string,
	jvm_args:            string,
	workers_max:         int,
	kotlin:              bool,
	repositories:        []string,
}

Settings :: struct {
	base:     Map,
	configs:  map[string]Value,
	groups:   []string,
	advanced: bool,
}

Source :: struct {
	path:           string,
	name:           string,
	group:          string,
	includes:       []string,
	excludes:       []string,
	optional:       bool,
	build_phase:    string,
	type:           string,
	compiler_flags: []string,
}

Dependency_Kind :: enum {
	Target,
	Framework,
	Package,
	Maven,
	Unsupported,
}

Dependency :: struct {
	kind:          Dependency_Kind,
	name:          string,
	path:          string,
	configuration: string,
	product:       string,
	products:      []string,
	link:          bool,
	embed:         bool,
	weak:          bool,
}

Package :: struct {
	group:    string,
	artifact: string,
	version:  string,
}

Info :: struct {
	present:    bool,
	path:       string,
	xml:        string,
	properties: Map,
}

Script :: struct {
	path:                       string,
	script:                     string,
	name:                       string,
	shell:                      string,
	input_files:                []string,
	output_files:               []string,
	based_on_dependency_analysis: bool,
	run_only_when_installing:   bool,
}

Build_Field :: struct {
	name:    string,
	type:    string,
	value:   string,
	configs: []string,
}

Res_Value :: struct {
	name:    string,
	type:    string,
	value:   string,
	configs: []string,
}

External_Native_Kind :: enum {
	None,
	CMake,
	NdkBuild,
}

External_Native :: struct {
	present:   bool,
	conflict:  bool,
	kind:      External_Native_Kind,
	path:      string,
	version:   string,
	arguments: []string,
	c_flags:   []string,
	cpp_flags: []string,
	targets:   []string,
}

Native_Build :: struct {
	present: bool,
	command: string,
	args:    []string,
	abis:    []string,
	inputs:  []string,
	output:  string,
	env:     map[string]string,
}

Flavor :: struct {
	name:                   string,
	dimension:              string,
	application_id_suffix:  string,
	version_name_suffix:    string,
	min_sdk:                int,
	target_sdk:             int,
}

Signing_Config :: struct {
	name:                string,
	store_file:          string,
	store_password:      string,
	key_alias:           string,
	key_password:        string,
	store_type:          string,
	store_password_env:  string,
	key_password_env:    string,
}

Android_Target :: struct {
	compile_sdk:           int,
	min_sdk:               int,
	target_sdk:            int,
	version_code:          int,
	version_name:          string,
	namespace:             string,
	application_id:        string,
	build_tools_version:   string,
	ndk_version:           string,
	abi_filters:           []string,
	build_config_fields:   [dynamic]Build_Field,
	res_values:            [dynamic]Res_Value,
	manifest_placeholders: map[string]string,
	proguard_files:        []string,
	minify_enabled:        bool,
	minify_set:            bool,
	shrink_resources:      bool,
	view_binding:          bool,
	compose:               bool,
	build_config:          bool,
	external:              External_Native,
	native_build:          Native_Build,
	flavor_dimensions:     []string,
	flavors:               [dynamic]Flavor,
	signing_configs:       [dynamic]Signing_Config,
}

Target :: struct {
	name:                 string,
	language:             string,
	module_name:          string,
	kind:                 Target_Kind,
	platform:             string,
	deployment_target:    int,
	sources:              []Source,
	settings:             Settings,
	dependencies:         []Dependency,
	info:                 Info,
	android:              Android_Target,
	pre_scripts:          []Script,
	post_compile_scripts: []Script,
	post_scripts:         []Script,
	config_files:         map[string]string,
}

Project :: struct {
	name:            string,
	base_dir:        string,
	output_dir:      string,
	options:         Project_Options,
	configs:         []Build_Type,
	targets:         []Target,
	packages:        map[string]Package,
	setting_groups:  map[string]Value,
	project_settings: Settings,
	bindings:         []Binding_Config,
	raw:             Map,
	warnings:        [dynamic]string,
}

parse_project :: proc(loaded: Spec_Load_Result, output_override: string) -> (Project, string) {
	m := resolve_target_templates(loaded.value)
	name := m_get_string(m, "name")
	if name == "" do return {}, "spec missing required key: name"

	project := Project {
		name             = name,
		warnings         = make([dynamic]string),
		base_dir         = loaded.base_dir,
		raw              = m,
		packages         = make(map[string]Package),
		setting_groups   = make(map[string]Value),
		project_settings = parse_settings(m_get_or(m, "settings", m_empty())),
	}
	project.options = parse_project_options(m_get_or(m, "options", m_empty()))
	project.output_dir = output_override
	if project.output_dir == "" do project.output_dir = project.options.output_dir
	if project.output_dir == "" do project.output_dir = project.options.android.output_dir
	if project.output_dir == "" do project.output_dir = "android"
	if !filepath.is_abs(project.output_dir) {
		project.output_dir = join_path(project.base_dir, project.output_dir)
	}

	project.configs = parse_configs(m_get_or(m, "configs", nil))
	if project.options.min_androidgen_version != "" && !version_at_least(VERSION, project.options.min_androidgen_version) {
		return {}, fmt.tprintf("spec requires androidgen %s or newer (this is %s)", project.options.min_androidgen_version, VERSION)
	}
	if project.options.default_config != "" && !config_exists(project.configs, project.options.default_config) {
		return {}, fmt.tprintf("defaultConfig %q is not one of the configured configs", project.options.default_config)
	}
	switch project.options.setting_presets {
	case "all", "project", "targets", "none":
	case:
		return {}, fmt.tprintf("invalid settingPresets value %q", project.options.setting_presets)
	}

	if sg, has := m_get(m, "settingGroups"); has {
		if sgm, ok2 := sg.(Map); ok2 {
			for k in sgm.keys do project.setting_groups[k] = sgm.values[k]
		}
	}
	if pk, has := m_get(m, "packages"); has {
		if pkm, ok2 := pk.(Map); ok2 {
			for k in pkm.keys {
				project.packages[k] = parse_package(pkm.values[k])
			}
		}
	}

	if targets_v, has := m_get(m, "targets"); has {
		if tm, ok2 := targets_v.(Map); ok2 {
			for key in tm.keys {
				target, skip, err := parse_target(&project, key, tm.values[key])
				if err != "" do return {}, err
				if skip do continue
				project.targets = append_target(project.targets, target)
			}
		}
	}
	if len(project.targets) == 0 do return {}, "spec contains no Android targets"
	bindings, bindings_err := parse_bindings(m, &project, loaded.disable_env)
	if bindings_err != "" do return {}, bindings_err
	project.bindings = bindings
	for t in project.targets {
		if t.android.native_build.present && len(t.android.native_build.abis) == 0 {
			return {}, fmt.tprintf("target %s: nativeBuild requires abis or abiFilters", t.name)
		}
	}
	for i in 0 ..< len(project.targets) {
		for j in i + 1 ..< len(project.targets) {
			if project.targets[i].module_name == project.targets[j].module_name {
				return {}, fmt.tprintf("targets %s and %s both map to Gradle module %s", project.targets[i].name, project.targets[j].name, project.targets[i].module_name)
			}
		}
	}
	collect_project_warnings(&project, m)
	resolve_target_dependencies(&project)
	return project, ""
}

append_target :: proc(arr: []Target, t: Target) -> []Target {
	out := make([]Target, len(arr) + 1)
	copy(out[:len(arr)], arr)
	out[len(arr)] = t
	return out
}

collect_project_warnings :: proc(project: ^Project, m: Map) {
	unsupported_top := []string{"breakpoints", "fileGroups", "attributes", "schemes", "schemeTemplates", "projectReferences", "aggregateTargets", "localPackages"}
	for key in unsupported_top {
		if m_has(m, key) do append(&project.warnings, fmt.tprintf("project.%s is not supported on Android and is ignored", key))
	}
	if ov, has := m_get(m, "options"); has {
		if om, ok := ov.(Map); ok {
			unsupported_options := []string{"xcodeVersion", "projectFormat", "developmentLanguage", "usesTabs", "indentWidth", "tabWidth", "groupSortPosition", "groupOrdering", "fileTypes", "generateEmptyDirectories", "findCarthageFrameworks", "localPackagesGroup", "schemePathPrefix", "useBaseInternationalization", "carthageBuildPath", "carthageExecutablePath", "transitivelyLinkDependencies", "defaultSourceDirectoryType", "minimumXcodeGenVersion"}
			for key in unsupported_options {
				if m_has(om, key) do append(&project.warnings, fmt.tprintf("options.%s is not supported on Android and is ignored", key))
			}
		}
	}
	if tv, has := m_get(m, "targets"); has {
		if tm, ok := tv.(Map); ok {
			for name in tm.keys {
				t, ok2 := tm.values[name].(Map)
				if !ok2 do continue
				unsupported_target := []string{"entitlements", "buildRules", "buildToolPlugins", "legacy", "attributes", "supportedDestinations", "onlyCopyFilesOnInstall", "requiresObjCLinking", "transitivelyLinkDependencies", "directlyEmbedCarthageDependencies", "putResourcesBeforeSourcesBuildPhase", "scheme"}
				for key in unsupported_target {
					if m_has(t, key) do append(&project.warnings, fmt.tprintf("targets.%s.%s is not supported on Android and is ignored", name, key))
				}
				if sv, has2 := m_get(t, "sources"); has2 {
					if sa, ok3 := sv.([]Value); ok3 {
						for item in sa {
							if sm, ok4 := item.(Map); ok4 {
								unsupported_source := []string{"headerVisibility", "resourceTags", "destinationFilters", "inferDestinationFiltersByPath", "explicitFolders", "createIntermediateGroups", "attributes"}
								for key in unsupported_source {
									if m_has(sm, key) do append(&project.warnings, fmt.tprintf("targets.%s.sources.%s is not supported on Android and is ignored", name, key))
								}
							}
						}
					}
				}
			}
		}
	}
}

config_exists :: proc(configs: []Build_Type, name: string) -> bool {
	for c in configs {
		if strings.equal_fold(c.display, name) || strings.equal_fold(c.name, name) do return true
	}
	return false
}

version_at_least :: proc(current, required: string) -> bool {
	c := strings.split(current, ".")
	r := strings.split(required, ".")
	for i in 0 ..< 3 {
		cv := 0
		rv := 0
		if i < len(c) do cv = value_int(c[i], 0)
		if i < len(r) do rv = value_int(r[i], 0)
		if cv > rv do return true
		if cv < rv do return false
	}
	return true
}

parse_project_options :: proc(v: Value) -> Project_Options {
	repos := make([]string, 2)
	repos[0] = "google()"
	repos[1] = "mavenCentral()"
	opts := Project_Options {
		setting_presets = "all",
		android = Android_Options {
			compile_sdk         = 35,
			agp_version         = "8.7.3",
			gradle_version      = "8.12",
			kotlin_version      = "2.0.21",
			jvm_args            = "-Xmx2048m",
			workers_max         = 2,
			kotlin              = true,
			repositories        = repos,
		},
	}
	m, ok := v.(Map)
	if !ok do return opts
	opts.bundle_id_prefix = m_get_string(m, "bundleIdPrefix")
	opts.setting_presets = m_get_string_or(m, "settingPresets", "all")
	opts.default_config = m_get_string(m, "defaultConfig")
	opts.pre_gen_command = m_get_string(m, "preGenCommand")
	opts.post_gen_command = m_get_string(m, "postGenCommand")
	opts.output_dir = m_get_string(m, "outputDirectory")
	opts.min_androidgen_version = m_get_string(m, "minimumAndroidGenVersion")
	opts.deployment_target = parse_deployment_target(m_get_or(m, "deploymentTarget", nil))

	if av, has := m_get(m, "android"); has {
		if am, ok2 := av.(Map); ok2 {
			parse_android_options(&opts.android, am)
		}
	}
	return opts
}

parse_android_options :: proc(a: ^Android_Options, m: Map) {
	for k in m.keys {
		v := m.values[k]
		switch k {
		case "compileSdk":
			a.compile_sdk = value_int(v, a.compile_sdk)
		case "buildToolsVersion":
			a.build_tools_version = value_string(v)
		case "ndkVersion":
			a.ndk_version = value_string(v)
		case "agpVersion":
			a.agp_version = value_string(v)
		case "gradleVersion":
			a.gradle_version = value_string(v)
		case "gradleSha256":
			a.gradle_sha256 = value_string(v)
		case "kotlinVersion":
			a.kotlin_version = value_string(v)
		case "outputDirectory":
			a.output_dir = value_string(v)
		case "jvmArgs":
			a.jvm_args = value_string(v)
		case "workersMax":
			a.workers_max = value_int(v, a.workers_max)
		case "kotlin":
			a.kotlin = value_bool(v, a.kotlin)
		case "repositories":
			if arr, ok := v.([]Value); ok {
				repos := make([dynamic]string)
				for item in arr do append(&repos, value_string(item))
				a.repositories = repos[:]
			}
		}
	}
}

parse_deployment_target :: proc(v: Value) -> int {
	#partial switch x in v {
	case i64:
		return int(x)
	case f64:
		return int(x)
	case string:
		if strings.contains(x, ".") {
			if f, ok := strconv.parse_f64(x); ok do return int(f)
		}
		if n, ok := strconv.parse_i64(x); ok do return int(n)
	case Map:
		if av, ok := m_get(x, "Android"); ok {
			return value_int(av, 0)
		}
	}
	return 0
}

parse_configs :: proc(v: Value) -> []Build_Type {
	out := make([dynamic]Build_Type)
	m, ok := v.(Map)
	if !ok || len(m.keys) == 0 {
		append(&out, Build_Type{name = "debug", display = "Debug", kind = "debug"})
		append(&out, Build_Type{name = "release", display = "Release", kind = "release"})
		return out[:]
	}
	for k in m.keys {
		kind := value_string(m.values[k])
		name := normalize_build_type(k)
		append(&out, Build_Type{name = name, display = k, kind = kind})
	}
	// XcodeGen sorts configurations by name.
	for i in 1 ..< len(out) {
		j := i
		for j > 0 && out[j - 1].display > out[j].display {
			out[j - 1], out[j] = out[j], out[j - 1]
			j -= 1
		}
	}
	return out[:]
}

normalize_build_type :: proc(s: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	for c in s {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			strings.write_rune(&out, c)
		}
	}
	res, _ := strings.to_lower(strings.to_string(out))
	return res
}

sanitize_module_name :: proc(s: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	for c in s {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			strings.write_rune(&out, c)
		} else {
			strings.write_byte(&out, '_')
		}
	}
	res, _ := strings.to_lower(strings.to_string(out))
	if res == "" do return "module"
	return res
}

parse_package :: proc(v: Value) -> Package {
	m, ok := v.(Map)
	if !ok do return Package{}
	return Package {
		group = m_get_string(m, "group"),
		artifact = m_get_string(m, "artifact"),
		version = m_get_string(m, "version"),
	}
}

parse_target :: proc(project: ^Project, key: string, v: Value) -> (Target, bool, string) {
	m, ok := v.(Map)
	if !ok do return {}, true, fmt.tprintf("target %s must be a mapping", key)
	name := m_get_string(m, "name")
	if name == "" do name = key
	platform := m_get_string_or(m, "platform", "Android")
	if !strings.equal_fold(platform, "Android") && !strings.equal_fold(platform, "auto") {
		append(&project.warnings, fmt.tprintf("target %s: platform %s is not Android, skipping", name, platform))
		return {}, true, ""
	}
	type_str := m_get_string(m, "type")
	kind: Target_Kind
	switch type_str {
	case "application":
		kind = .Application
	case "framework", "framework.static", "library", "library.dynamic", "library.static", "android-library":
		kind = .Library
	case "tool", "java-library", "kotlin-jvm":
		kind = .Jvm
	case:
		return {}, true, fmt.tprintf("target %s: unsupported target type %q", name, type_str)
	}

	target := Target {
		name        = name,
		module_name = sanitize_module_name(name),
		kind        = kind,
		platform    = platform,
		language    = m_get_string(m, "language"),
		settings    = parse_settings(m_get_or(m, "settings", m_empty())),
		config_files = make(map[string]string),
	}
	if target.language == "" {
		switch type_str {
		case "java-library": target.language = "java"
		case "kotlin-jvm": target.language = "kotlin"
		}
	}
	if target.language != "" && target.language != "java" && target.language != "kotlin" {
		return {}, false, fmt.tprintf("target %s: language must be java or kotlin", name)
	}
	target.deployment_target = parse_deployment_target(m_get_or(m, "deploymentTarget", nil))
	if target.deployment_target == 0 do target.deployment_target = project.options.deployment_target
	if target.deployment_target == 0 do target.deployment_target = 21

	if sv, has := m_get(m, "sources"); has {
		target.sources = parse_sources(sv)
	}
	add_legacy_sources(&target, m, project.base_dir)
	if av, has := m_get(m, "android"); has {
		if am, ok2 := av.(Map); ok2 {
			parse_android_target(&target.android, am)
		}
		if target.android.external.present && target.android.external.conflict {
			return {}, false, fmt.tprintf("target %s: externalNativeBuild must specify exactly one of cmake or ndkBuild", name)
		}
		if target.android.external.present && target.android.external.path == "" {
			return {}, false, fmt.tprintf("target %s: externalNativeBuild.path is required", name)
		}
		if target.android.native_build.present && target.android.native_build.command == "" {
			return {}, false, fmt.tprintf("target %s: nativeBuild.command is required", name)
		}
	}
	if dv, has := m_get(m, "dependencies"); has {
		target.dependencies = parse_dependencies(dv)
	}
	if iv, has := m_get(m, "info"); has {
		target.info = parse_info(iv)
	}
	if sv, has := m_get(m, "preBuildScripts"); has do target.pre_scripts = parse_scripts(sv)
	if sv, has := m_get(m, "postCompileScripts"); has do target.post_compile_scripts = parse_scripts(sv)
	if sv, has := m_get(m, "postBuildScripts"); has do target.post_scripts = parse_scripts(sv)
	if cv, has := m_get(m, "configFiles"); has {
		if cm, ok2 := cv.(Map); ok2 {
			for k in cm.keys do target.config_files[k] = value_string(cm.values[k])
		}
	}

	apply_settings_to_android(project, &target)
	return target, false, ""
}

parse_sources :: proc(v: Value) -> []Source {
	out := make([dynamic]Source)
	add := proc(out: ^[dynamic]Source, item: Value) {
		if s, ok := item.(string); ok {
			append(out, Source{path = s})
			return
		}
		if m, ok := item.(Map); ok {
			src := Source {
				path = m_get_string(m, "path"),
				name = m_get_string(m, "name"),
				group = m_get_string(m, "group"),
				optional = value_bool(m_get_or(m, "optional", false)),
				build_phase = parse_build_phase(m_get_or(m, "buildPhase", nil)),
				type = m_get_string(m, "type"),
				includes = value_array_strings(m_get_or(m, "includes", nil)),
				excludes = value_array_strings(m_get_or(m, "excludes", nil)),
				compiler_flags = value_array_strings(m_get_or(m, "compilerFlags", nil)),
			}
			append(out, src)
		}
	}
	if s, ok := v.(string); ok {
		append(&out, Source{path = s})
	} else if a, ok := v.([]Value); ok {
		for item in a do add(&out, item)
	} else if m, ok := v.(Map); ok {
		add(&out, m)
	}
	return out[:]
}

parse_build_phase :: proc(v: Value) -> string {
	if s, ok := v.(string); ok do return s
	if m, ok := v.(Map); ok {
		if cm, ok2 := m_get(m, "copyFiles"); ok2 {
			if c, ok3 := cm.(Map); ok3 do return m_get_string(c, "destination")
		}
	}
	return ""
}

parse_dependencies :: proc(v: Value) -> []Dependency {
	out := make([dynamic]Dependency)
	arr, ok := v.([]Value)
	if !ok do return out[:]
	for item in arr {
		m, ok2 := item.(Map)
		if !ok2 do continue
		dep := Dependency{link = true, embed = true}
		if tv, has := m_get(m, "target"); has {
			dep.kind = .Target
			dep.name = value_string(tv)
		} else if fv, has := m_get(m, "framework"); has {
			dep.kind = .Framework
			dep.path = value_string(fv)
		} else if pv, has := m_get(m, "package"); has {
			dep.kind = .Package
			dep.name = value_string(pv)
		} else if mv, has := m_get(m, "maven"); has {
			dep.kind = .Maven
			dep.name = value_string(mv)
		} else if cv, has := m_get(m, "carthage"); has {
			dep.kind = .Unsupported
			dep.name = strings.concatenate([]string{"carthage:", value_string(cv)})
		} else if sv, has := m_get(m, "sdk"); has {
			dep.kind = .Unsupported
			dep.name = strings.concatenate([]string{"sdk:", value_string(sv)})
		} else if bv, has := m_get(m, "bundle"); has {
			dep.kind = .Unsupported
			dep.name = strings.concatenate([]string{"bundle:", value_string(bv)})
		} else {
			continue
		}
		dep.configuration = m_get_string(m, "configuration")
		dep.product = m_get_string(m, "product")
		dep.products = value_array_strings(m_get_or(m, "products", nil))
		dep.link = value_bool(m_get_or(m, "link", true), true)
		dep.embed = value_bool(m_get_or(m, "embed", true), true)
		dep.weak = value_bool(m_get_or(m, "weak", false), false)
		append(&out, dep)
	}
	return out[:]
}

parse_info :: proc(v: Value) -> Info {
	m, ok := v.(Map)
	if !ok do return Info{}
	props := m_empty()
	if pv, has := m_get(m, "properties"); has {
		if pm, ok2 := pv.(Map); ok2 do props = pm
	}
	return Info {
		present = true,
		path = m_get_string(m, "path"),
		xml = m_get_string(m, "xml"),
		properties = props,
	}
}

parse_scripts :: proc(v: Value) -> []Script {
	out := make([dynamic]Script)
	arr, ok := v.([]Value)
	if !ok do return out[:]
	for item in arr {
		m, ok2 := item.(Map)
		if !ok2 do continue
		append(&out, Script{
			path = m_get_string(m, "path"),
			script = m_get_string(m, "script"),
			name = m_get_string(m, "name"),
			shell = m_get_string_or(m, "shell", "/bin/sh"),
			input_files = value_array_strings(m_get_or(m, "inputFiles", nil)),
			output_files = value_array_strings(m_get_or(m, "outputFiles", nil)),
			based_on_dependency_analysis = value_bool(m_get_or(m, "basedOnDependencyAnalysis", true), true),
			run_only_when_installing = value_bool(m_get_or(m, "runOnlyWhenInstalling", false), false),
		})
	}
	return out[:]
}

parse_android_target :: proc(a: ^Android_Target, m: Map) {
	for k in m.keys {
		v := m.values[k]
		switch k {
		case "compileSdk":
			a.compile_sdk = value_int(v)
		case "minSdk":
			a.min_sdk = value_int(v)
		case "targetSdk":
			a.target_sdk = value_int(v)
		case "versionCode":
			a.version_code = value_int(v)
		case "versionName":
			a.version_name = value_string(v)
		case "namespace":
			a.namespace = value_string(v)
		case "applicationId":
			a.application_id = value_string(v)
		case "buildToolsVersion":
			a.build_tools_version = value_string(v)
		case "ndkVersion":
			a.ndk_version = value_string(v)
		case "abiFilters":
			a.abi_filters = value_array_strings(v)
		case "proguardFiles":
			a.proguard_files = value_array_strings(v)
		case "minifyEnabled":
			a.minify_enabled = value_bool(v)
			a.minify_set = true
		case "shrinkResources":
			a.shrink_resources = value_bool(v)
		case "buildFeatures":
			if bm, ok := v.(Map); ok {
				a.view_binding = value_bool(m_get_or(bm, "viewBinding", false))
				a.compose = value_bool(m_get_or(bm, "compose", false))
				a.build_config = value_bool(m_get_or(bm, "buildConfig", false))
			}
		case "buildConfigFields":
			if bm, ok := v.(Map); ok {
				for name in bm.keys {
					append(&a.build_config_fields, parse_build_field(name, bm.values[name]))
				}
			}
		case "resValues":
			if rm, ok := v.(Map); ok {
				for name in rm.keys {
					append(&a.res_values, parse_res_value(name, rm.values[name]))
				}
			}
		case "manifestPlaceholders":
			if pm, ok := v.(Map); ok {
				a.manifest_placeholders = make(map[string]string)
				for name in pm.keys do a.manifest_placeholders[name] = value_string(pm.values[name])
			}
		case "externalNativeBuild":
			if em, ok := v.(Map); ok {
				parse_external_native(&a.external, em)
			}
		case "nativeBuild":
			if nm, ok := v.(Map); ok {
				a.native_build = parse_native_build(nm)
			}
		case "flavorDimensions":
			a.flavor_dimensions = parse_string_or_array(v)
		case "productFlavors":
			if fm, ok := v.(Map); ok {
				for fname in fm.keys {
					if fv, ok2 := fm.values[fname].(Map); ok2 {
						append(&a.flavors, parse_flavor(fname, fv))
					}
				}
			}
		case "signingConfigs":
			if sm, ok := v.(Map); ok {
				for sname in sm.keys {
					if sv, ok2 := sm.values[sname].(Map); ok2 {
						append(&a.signing_configs, parse_signing_config(sname, sv))
					}
				}
			}
		}
	}
}

parse_string_or_array :: proc(v: Value) -> []string {
	if v == nil do return nil
	return value_array_strings(v)
}

parse_external_native :: proc(e: ^External_Native, m: Map) {
	e.present = true
	if cm, has := m_get(m, "cmake"); has {
		if c, ok := cm.(Map); ok {
			if e.kind != .None do e.conflict = true
			e.kind = .CMake
			e.path = m_get_string(c, "path")
			e.version = m_get_string(c, "version")
			e.arguments = parse_string_or_array(m_get_or(c, "arguments", nil))
			e.c_flags = parse_string_or_array(m_get_or(c, "cFlags", nil))
			e.cpp_flags = parse_string_or_array(m_get_or(c, "cppFlags", nil))
			e.targets = parse_string_or_array(m_get_or(c, "targets", nil))
		}
	}
	if nm, has := m_get(m, "ndkBuild"); has {
		if n, ok := nm.(Map); ok {
			if e.kind != .None do e.conflict = true
			e.kind = .NdkBuild
			e.path = m_get_string(n, "path")
			e.arguments = parse_string_or_array(m_get_or(n, "arguments", nil))
		}
	}
}

parse_native_build :: proc(m: Map) -> Native_Build {
	nb := Native_Build{present = true, env = make(map[string]string)}
	nb.command = m_get_string(m, "command")
	nb.args = parse_string_or_array(m_get_or(m, "args", nil))
	nb.abis = parse_string_or_array(m_get_or(m, "abis", nil))
	nb.inputs = parse_string_or_array(m_get_or(m, "inputs", nil))
	nb.output = m_get_string(m, "output")
	if ev, has := m_get(m, "env"); has {
		if em, ok := ev.(Map); ok {
			for k in em.keys do nb.env[k] = value_string(em.values[k])
		}
	}
	return nb
}

parse_flavor :: proc(name: string, m: Map) -> Flavor {
	return Flavor{
		name = name,
		dimension = m_get_string(m, "dimension"),
		application_id_suffix = m_get_string(m, "applicationIdSuffix"),
		version_name_suffix = m_get_string(m, "versionNameSuffix"),
		min_sdk = value_int(m_get_or(m, "minSdk", 0)),
		target_sdk = value_int(m_get_or(m, "targetSdk", 0)),
	}
}

parse_signing_config :: proc(name: string, m: Map) -> Signing_Config {
	return Signing_Config{
		name = name,
		store_file = m_get_string(m, "storeFile"),
		store_password = m_get_string(m, "storePassword"),
		key_alias = m_get_string(m, "keyAlias"),
		key_password = m_get_string(m, "keyPassword"),
		store_type = m_get_string(m, "storeType"),
		store_password_env = m_get_string(m, "storePasswordEnv"),
		key_password_env = m_get_string(m, "keyPasswordEnv"),
	}
}

parse_build_field :: proc(name: string, v: Value) -> Build_Field {
	m, ok := v.(Map)
	if !ok do return Build_Field{name = name, type = "String", value = value_string(v)}
	return Build_Field{
		name = name,
		type = m_get_string_or(m, "type", "String"),
		value = m_get_string(m, "value"),
		configs = value_array_strings(m_get_or(m, "configs", nil)),
	}
}

parse_res_value :: proc(name: string, v: Value) -> Res_Value {
	m, ok := v.(Map)
	if !ok do return Res_Value{name = name, type = "string", value = value_string(v)}
	return Res_Value{
		name = name,
		type = m_get_string_or(m, "type", "string"),
		value = m_get_string(m, "value"),
		configs = value_array_strings(m_get_or(m, "configs", nil)),
	}
}

add_legacy_sources :: proc(t: ^Target, m: Map, base_dir: string) {
	if v, has := m_get(m, "manifest"); has {
		t.sources = append_source(t.sources, Source{path = value_string(v), build_phase = "manifest"})
	}
	if v, has := m_get(m, "res"); has {
		t.sources = append_source(t.sources, Source{path = value_string(v), build_phase = "res"})
	}
	if v, has := m_get(m, "java"); has {
		for s in value_array_strings(v) {
			t.sources = append_source(t.sources, Source{path = s, build_phase = "java"})
		}
	}
	if v, has := m_get(m, "jni_libs"); has {
		t.sources = append_source(t.sources, Source{path = value_string(v), build_phase = "jniLibs"})
	}
	if v, has := m_get(m, "proguard"); has {
		t.sources = append_source(t.sources, Source{path = value_string(v), build_phase = "proguard"})
	}
}

append_source :: proc(arr: []Source, s: Source) -> []Source {
	out := make([]Source, len(arr) + 1)
	copy(out[:len(arr)], arr)
	out[len(arr)] = s
	return out
}

parse_settings :: proc(v: Value) -> Settings {
	s := Settings{base = m_empty(), configs = make(map[string]Value)}
	m, ok := v.(Map)
	if !ok do return s
	has_advanced := m_has(m, "base") || m_has(m, "configs") || m_has(m, "groups") || m_has(m, "presets")
	if !has_advanced {
		s.base = m
		return s
	}
	s.advanced = true
	if b, ok2 := m_get(m, "base"); ok2 {
		if bm, ok3 := b.(Map); ok3 do s.base = bm
	}
	if g, ok2 := m_get(m, "groups"); ok2 {
		s.groups = value_array_strings(g)
	}
	if g, ok2 := m_get(m, "presets"); ok2 && len(s.groups) == 0 {
		s.groups = value_array_strings(g)
	}
	if c, ok2 := m_get(m, "configs"); ok2 {
		if cm, ok3 := c.(Map); ok3 {
			for k in cm.keys do s.configs[k] = cm.values[k]
		}
	}
	return s
}

resolve_settings :: proc(project: ^Project, settings: Settings, config_display: string, config_name: string) -> Map {
	return resolve_settings_depth(project, settings, config_display, config_name, 0)
}

resolve_settings_depth :: proc(project: ^Project, settings: Settings, config_display: string, config_name: string, depth: int) -> Map {
	if depth > 16 do return m_empty()
	out := m_empty()
	for group in settings.groups {
		if gv, has := project.setting_groups[group]; has {
			gsettings := parse_settings(gv)
			gs := resolve_settings_depth(project, gsettings, config_display, config_name, depth + 1)
			out = m_merge(out, gs)
		}
	}
	out = m_merge(out, settings.base)
	// Exact config match wins over substring matching. Sort keys so merge order
	// is deterministic.
	keys := make([dynamic]string)
	for k in settings.configs do append(&keys, k)
	sort_strings(keys[:])
	for k in keys {
		if strings.equal_fold(k, config_display) || strings.equal_fold(k, config_name) {
			if cm, ok := settings.configs[k].(Map); ok do out = m_merge(out, cm)
		}
	}
	display_lower, _ := strings.to_lower(config_display)
	name_lower, _ := strings.to_lower(config_name)
	for k in keys {
		if strings.equal_fold(k, config_display) || strings.equal_fold(k, config_name) do continue
		// A key that exactly names any config is not a substring match for the
		// other configs. This mirrors XcodeGen: "Release" matches only Release,
		// not "Staging Release".
		exact_other := false
		for cfg in project.configs {
			if strings.equal_fold(k, cfg.display) || strings.equal_fold(k, cfg.name) {
				exact_other = true
				break
			}
		}
		if exact_other do continue
		key_lower, _ := strings.to_lower(k)
		if strings.contains(display_lower, key_lower) || strings.contains(name_lower, key_lower) {
			if cm, ok := settings.configs[k].(Map); ok do out = m_merge(out, cm)
		}
	}
	return out
}

apply_settings_to_android :: proc(project: ^Project, t: ^Target) {
	// Base settings first, then per-config settings, with target android: block
	// taking precedence over aliases.
	base := resolve_settings(project, project.project_settings, t.name, t.name)
	base = m_merge(base, resolve_settings(project, t.settings, t.name, t.name))
	// Native android: fields win over aliases from settings.
	if t.android.application_id == "" {
		if app_id := setting_first(base, []string{"applicationId", "PRODUCT_BUNDLE_IDENTIFIER"}); app_id != "" {
			t.android.application_id = app_id
		}
	}
	if t.android.namespace == "" {
		if ns := setting_first(base, []string{"namespace"}); ns != "" {
			t.android.namespace = ns
		}
	}
	if t.android.version_name == "" {
		if v := setting_first(base, []string{"versionName", "MARKETING_VERSION"}); v != "" {
			t.android.version_name = v
		}
	}
	if t.android.version_code == 0 {
		if v := setting_first(base, []string{"versionCode", "CURRENT_PROJECT_VERSION"}); v != "" {
			t.android.version_code = value_int(v, 0)
		}
	}
	if t.android.min_sdk == 0 {
		if v := setting_first(base, []string{"minSdk"}); v != "" {
			t.android.min_sdk = value_int(v, 0)
		}
	}
	if t.android.target_sdk == 0 {
		if v := setting_first(base, []string{"targetSdk"}); v != "" {
			t.android.target_sdk = value_int(v, 0)
		}
	}
	if t.android.compile_sdk == 0 {
		if v := setting_first(base, []string{"compileSdk"}); v != "" {
			t.android.compile_sdk = value_int(v, 0)
		}
	}
	if len(t.android.proguard_files) == 0 {
		if v := setting_first(base, []string{"proguardFiles"}); v != "" {
			t.android.proguard_files = strings.split(v, ",")
		}
	}
	if t.android.application_id == "" && project.options.bundle_id_prefix != "" {
		t.android.application_id = strings.concatenate([]string{project.options.bundle_id_prefix, ".", t.module_name})
	}
	if t.android.namespace == "" do t.android.namespace = t.android.application_id
	if t.android.min_sdk == 0 do t.android.min_sdk = t.deployment_target
	if t.android.compile_sdk == 0 do t.android.compile_sdk = project.options.android.compile_sdk
	if t.android.target_sdk == 0 do t.android.target_sdk = t.android.compile_sdk
	if t.android.build_tools_version == "" do t.android.build_tools_version = project.options.android.build_tools_version
	if t.android.ndk_version == "" do t.android.ndk_version = project.options.android.ndk_version
	if t.android.version_code == 0 do t.android.version_code = 1
	if t.android.version_name == "" do t.android.version_name = "1.0"
	if t.android.native_build.present && len(t.android.native_build.abis) == 0 {
		t.android.native_build.abis = t.android.abi_filters
	}
	if t.android.compile_sdk == 0 do t.android.compile_sdk = 35
	if t.kind == .Application && t.android.application_id == "" {
		append(&project.warnings, fmt.tprintf("target %s: no applicationId or bundleIdPrefix", t.name))
	}
}

setting_first :: proc(m: Map, keys: []string) -> string {
	for k in keys {
		if v, ok := m_get(m, k); ok {
			return value_string(v)
		}
	}
	return ""
}

resolve_target_dependencies :: proc(project: ^Project) {
	for t, ti in project.targets {
		for dep, di in t.dependencies {
			if dep.kind == .Package && dep.name != "" {
				if _, ok := project.packages[dep.name]; !ok {
					append(&project.warnings, fmt.tprintf("target %s: unknown package %s", t.name, dep.name))
				}
			}
			if dep.kind == .Target && dep.name != "" {
				if find_target(project, dep.name) == nil {
					append(&project.warnings, fmt.tprintf("target %s: unknown target dependency %s", t.name, dep.name))
				}
			}
			if dep.kind == .Unsupported {
				append(&project.warnings, fmt.tprintf("target %s: dependency %s is not supported on Android", t.name, dep.name))
			}
			_ = di
		}
		_ = ti
	}
}

find_target :: proc(project: ^Project, name: string) -> ^Target {
	for t, i in project.targets {
		if t.name == name || strings.equal_fold(t.name, name) {
			return &project.targets[i]
		}
	}
	return nil
}

load_and_parse_project :: proc(spec_path, project_root, output_override: string, disable_env: bool) -> (Project, Spec_Load_Result, string) {
	if is_legacy_file(spec_path) {
		return load_legacy_project(spec_path, project_root, output_override)
	}
	loaded, err := load_spec_opts(spec_path, project_root, disable_env)
	if err != "" do return {}, {}, err
	project, perr := parse_project(loaded, output_override)
	if perr != "" do return {}, loaded, perr
	return project, loaded, ""
}
