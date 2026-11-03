package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

gline :: proc(b: ^strings.Builder, level: int, text: string) {
	for _ in 0 ..< level * 4 do strings.write_byte(b, ' ')
	strings.write_string(b, text)
	strings.write_byte(b, '\n')
}

gq :: proc(s: string) -> string {
	escaped, _ := strings.replace_all(s, "\\", "\\\\")
	escaped, _ = strings.replace_all(escaped, "'", "\\'")
	return strings.concatenate([]string{"'", escaped, "'"})
}

write_text_file :: proc(path, content: string) -> string {
	parent := filepath.dir(path)
	if parent != "" do os.mkdir_all(parent)
	if existing, err := os.read_entire_file_from_path(path, context.allocator); err == nil {
		if string(existing) == content do return ""
	}
	if err := os.write_entire_file_from_string(path, content); err != nil {
		return fmt.tprintf("cannot write %s", path)
	}
	return ""
}

emit_root_gradle :: proc(project: ^Project) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	settings_repos := project.options.android.repositories
	if len(settings_repos) == 0 do settings_repos = []string{"google()", "mavenCentral()"}

	gline(&b, 0, "pluginManagement {")
	gline(&b, 1, "repositories {")
	for repo in settings_repos do gline(&b, 2, repo)
	gline(&b, 2, "gradlePluginPortal()")
	gline(&b, 1, "}")
	gline(&b, 0, "}")
	gline(&b, 0, "dependencyResolutionManagement {")
	gline(&b, 1, "repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)")
	gline(&b, 1, "repositories {")
	for repo in settings_repos do gline(&b, 2, repo)
	gline(&b, 1, "}")
	gline(&b, 0, "}")
	gline(&b, 0, fmt.tprintf("rootProject.name = %s", gq(project.name)))
	include_line := "include "
	for t, i in project.targets {
		if i > 0 do include_line = strings.concatenate([]string{include_line, ", "})
		include_line = strings.concatenate([]string{include_line, gq(strings.concatenate([]string{":", t.module_name}))})
	}
	gline(&b, 0, include_line)
	return strings.to_string(b)
}

target_uses_kotlin :: proc(project: ^Project, target: ^Target) -> bool {
	if target.language == "java" do return false
	if target.language == "kotlin" do return true
	return project.options.android.kotlin
}

emit_root_build_gradle :: proc(project: ^Project) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	gline(&b, 0, "plugins {")
	has_app := false
	has_lib := false
	has_jvm := false
	has_kotlin_android := false
	has_kotlin_jvm := false
	for &t in project.targets {
		switch t.kind {
		case .Application:
			has_app = true
		case .Library:
			has_lib = true
		case .Jvm:
			has_jvm = true
		}
		if target_uses_kotlin(project, &t) {
			if t.kind == .Jvm {
				has_kotlin_jvm = true
			} else {
				has_kotlin_android = true
			}
		}
	}
	if has_app {
		gline(&b, 1, fmt.tprintf("id 'com.android.application' version %s apply false", gq(project.options.android.agp_version)))
	}
	if has_lib {
		gline(&b, 1, fmt.tprintf("id 'com.android.library' version %s apply false", gq(project.options.android.agp_version)))
	}
	if has_kotlin_android {
		gline(&b, 1, fmt.tprintf("id 'org.jetbrains.kotlin.android' version %s apply false", gq(project.options.android.kotlin_version)))
	}
	if has_kotlin_jvm {
		gline(&b, 1, fmt.tprintf("id 'org.jetbrains.kotlin.jvm' version %s apply false", gq(project.options.android.kotlin_version)))
	}
	gline(&b, 0, "}")
	return strings.to_string(b)
}

emit_gradle_properties :: proc(project: ^Project) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	gline(&b, 0, fmt.tprintf("org.gradle.jvmargs=%s", project.options.android.jvm_args))
	gline(&b, 0, fmt.tprintf("org.gradle.workers.max=%d", project.options.android.workers_max))
	gline(&b, 0, "android.useAndroidX=true")
	gline(&b, 0, "android.nonTransitiveRClass=true")
	gline(&b, 0, "kotlin.code.style=official")
	base := resolve_settings(project, project.project_settings, "Debug", "debug")
	for key in base.keys {
		switch key {
		case "PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
		     "applicationId", "namespace", "minSdk", "targetSdk", "compileSdk",
		     "versionCode", "versionName", "bundleIdPrefix":
			continue
		}
		gline(&b, 0, fmt.tprintf("%s=%s", key, value_string(base.values[key])))
	}
	return strings.to_string(b)
}

emit_wrapper_properties :: proc(project: ^Project) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	gline(&b, 0, "distributionBase=GRADLE_USER_HOME")
	gline(&b, 0, "distributionPath=wrapper/dists")
	gline(&b, 0, fmt.tprintf("distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip", project.options.android.gradle_version))
	gline(&b, 0, "zipStoreBase=GRADLE_USER_HOME")
	gline(&b, 0, "zipStorePath=wrapper/dists")
	if project.options.android.gradle_sha256 != "" {
		gline(&b, 0, fmt.tprintf("distributionSha256Sum=%s", project.options.android.gradle_sha256))
	}
	return strings.to_string(b)
}

is_known_setting :: proc(key: string) -> bool {
	switch key {
	case "applicationId", "namespace", "minSdk", "targetSdk", "compileSdk",
	     "versionCode", "versionName", "applicationIdSuffix", "versionNameSuffix",
	     "debuggable", "minifyEnabled", "shrinkResources", "proguardFiles",
	     "consumerProguardFiles", "testInstrumentationRunner", "multiDexEnabled",
	     "PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION":
		return true
	}
	return false
}

emit_ext_settings :: proc(b: ^strings.Builder, project: ^Project, target: ^Target) {
	base := resolve_settings(project, project.project_settings, "Debug", "debug")
	base = m_merge(base, resolve_settings(project, target.settings, "Debug", "debug"))
	keys := sorted_keys(base)
	first := true
	for key in keys {
		if is_known_setting(key) do continue
		value := base.values[key]
		if _, ok := value.(Map); ok do continue
		if _, ok := value.([]Value); ok do continue
		if first {
			gline(b, 0, "ext {")
			first = false
		}
		gline(b, 1, fmt.tprintf("%s = %s", key, gq(value_string(value))))
	}
	if !first do gline(b, 0, "}")
	if !first do strings.write_byte(b, '\n')
}

emit_module_gradle :: proc(project: ^Project, target: ^Target, module_dir: string) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)
	use_kotlin := target_uses_kotlin(project, target)
	switch target.kind {
	case .Application:
		gline(&b, 0, "plugins { id 'com.android.application' }")
		if use_kotlin do gline(&b, 0, "plugins { id 'org.jetbrains.kotlin.android' }")
	case .Library:
		gline(&b, 0, "plugins { id 'com.android.library' }")
		if use_kotlin do gline(&b, 0, "plugins { id 'org.jetbrains.kotlin.android' }")
	case .Jvm:
		gline(&b, 0, "plugins { id 'java-library' }")
		if use_kotlin do gline(&b, 0, "plugins { id 'org.jetbrains.kotlin.jvm' }")
	}
	strings.write_byte(&b, '\n')

	emit_ext_settings(&b, project, target)

	// Apply configuration scripts before the android block.
	for k in target.config_files {
		path := target.config_files[k]
		if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
		if strings.has_suffix(path, ".gradle") || strings.has_suffix(path, ".gradle.kts") {
			gline(&b, 0, fmt.tprintf("apply from: %s", gq(path)))
		}
	}

	if target.kind != .Jvm {
		gline(&b, 0, "android {")
		if target.android.namespace != "" do gline(&b, 1, fmt.tprintf("namespace %s", gq(target.android.namespace)))
		gline(&b, 1, fmt.tprintf("compileSdk %d", target.android.compile_sdk))
		if target.android.build_tools_version != "" do gline(&b, 1, fmt.tprintf("buildToolsVersion %s", gq(target.android.build_tools_version)))
		if target.android.ndk_version != "" do gline(&b, 1, fmt.tprintf("ndkVersion %s", gq(target.android.ndk_version)))
		emit_external_native_android(&b, project, target)
		gline(&b, 0, "")
		gline(&b, 1, "defaultConfig {")
		if target.kind == .Application && target.android.application_id != "" do gline(&b, 2, fmt.tprintf("applicationId %s", gq(target.android.application_id)))
		gline(&b, 2, fmt.tprintf("minSdk %d", target.android.min_sdk))
		if target.kind != .Library do gline(&b, 2, fmt.tprintf("targetSdk %d", target.android.target_sdk))
		if target.kind == .Application {
			gline(&b, 2, fmt.tprintf("versionCode %d", target.android.version_code))
			gline(&b, 2, fmt.tprintf("versionName %s", gq(target.android.version_name)))
		}
		if len(target.android.abi_filters) > 0 {
			gline(&b, 2, "ndk {")
			abi_line := "abiFilters "
			for abi, i in target.android.abi_filters {
				if i > 0 do abi_line = strings.concatenate([]string{abi_line, ", "})
				abi_line = strings.concatenate([]string{abi_line, gq(abi)})
			}
			gline(&b, 3, abi_line)
			gline(&b, 2, "}")
		}
		for field in target.android.build_config_fields {
			if len(field.configs) != 0 do continue
			gline(&b, 2, fmt.tprintf("buildConfigField %s, %s, %s", gq(field.type), gq(field.name), gq(field.value)))
		}
		for rv in target.android.res_values {
			if len(rv.configs) != 0 do continue
			gline(&b, 2, fmt.tprintf("resValue %s, %s, %s", gq(rv.type), gq(rv.name), gq(rv.value)))
		}
		if len(target.android.manifest_placeholders) > 0 {
			parts := make([dynamic]string)
			for k in target.android.manifest_placeholders {
				append(&parts, fmt.tprintf("%s: %s", k, gq(target.android.manifest_placeholders[k])))
			}
			gline(&b, 2, fmt.tprintf("manifestPlaceholders = [%s]", strings.join(parts[:], ", ")))
		}
		default_settings := resolve_settings(project, project.project_settings, "Debug", "debug")
		default_settings = m_merge(default_settings, resolve_settings(project, target.settings, "Debug", "debug"))
		if v := setting_first(default_settings, []string{"testInstrumentationRunner"}); v != "" {
			gline(&b, 2, fmt.tprintf("testInstrumentationRunner %s", gq(v)))
		}
		if v := setting_first(default_settings, []string{"multiDexEnabled"}); v != "" {
			gline(&b, 2, fmt.tprintf("multiDexEnabled %s", bool_gradle(value_bool(v))))
		}
		if target.kind == .Library {
			if v := setting_first(default_settings, []string{"consumerProguardFiles"}); v != "" {
				files := strings.split(v, ",")
				line_parts := make([dynamic]string)
				for f in files {
					path := strings.trim_space(f)
					if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
					append(&line_parts, gq(path))
				}
				gline(&b, 2, fmt.tprintf("consumerProguardFiles %s", strings.join(line_parts[:], ", ")))
			}
		}
		emit_external_native_default(&b, project, target)
		gline(&b, 1, "}")
		gline(&b, 0, "")
		emit_signing_configs(&b, project, target)
		gline(&b, 1, "buildTypes {")
		for cfg in project.configs {
			gline(&b, 2, strings.concatenate([]string{cfg.name, " {"}))
			cfg_settings := resolve_settings(project, project.project_settings, cfg.display, cfg.name)
			cfg_settings = m_merge(cfg_settings, resolve_settings(project, target.settings, cfg.display, cfg.name))
			if v := setting_first(cfg_settings, []string{"debuggable"}); v != "" {
				gline(&b, 3, fmt.tprintf("debuggable %s", bool_gradle(value_bool(v))))
			} else if cfg.kind == "debug" {
				gline(&b, 3, "debuggable true")
			}
			if v := setting_first(cfg_settings, []string{"minifyEnabled"}); v != "" {
				gline(&b, 3, fmt.tprintf("minifyEnabled %s", bool_gradle(value_bool(v))))
			} else if target.android.minify_set && cfg.kind == "release" {
				gline(&b, 3, fmt.tprintf("minifyEnabled %s", bool_gradle(target.android.minify_enabled)))
			}
			if v := setting_first(cfg_settings, []string{"shrinkResources"}); v != "" {
				gline(&b, 3, fmt.tprintf("shrinkResources %s", bool_gradle(value_bool(v))))
			} else if target.android.shrink_resources && cfg.kind == "release" {
				gline(&b, 3, "shrinkResources true")
			}
			if v := setting_first(cfg_settings, []string{"applicationIdSuffix"}); v != "" {
				gline(&b, 3, fmt.tprintf("applicationIdSuffix %s", gq(v)))
			}
			if v := setting_first(cfg_settings, []string{"versionNameSuffix"}); v != "" {
				gline(&b, 3, fmt.tprintf("versionNameSuffix %s", gq(v)))
			}
			signing_name := setting_first(cfg_settings, []string{"signingConfig"})
			if signing_name == "" {
				for sc in target.android.signing_configs {
					if strings.equal_fold(sc.name, cfg.name) do signing_name = sc.name
				}
			}
			if signing_name != "" {
				gline(&b, 3, fmt.tprintf("signingConfig signingConfigs.%s", signing_name))
			}
			if len(target.android.proguard_files) > 0 && cfg.kind == "release" {
				line := "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')"
				for pg in target.android.proguard_files {
					path := pg
					if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
					line = strings.concatenate([]string{line, ", ", gq(path)})
				}
				gline(&b, 3, line)
			}
			for field in target.android.build_config_fields {
				if len(field.configs) == 0 do continue
				if !field_for_config(field.configs, cfg.display, cfg.name) do continue
				gline(&b, 3, fmt.tprintf("buildConfigField %s, %s, %s", gq(field.type), gq(field.name), gq(field.value)))
			}
			for rv in target.android.res_values {
				if len(rv.configs) == 0 do continue
				if !field_for_config(rv.configs, cfg.display, cfg.name) do continue
				gline(&b, 3, fmt.tprintf("resValue %s, %s, %s", gq(rv.type), gq(rv.name), gq(rv.value)))
			}
			gline(&b, 2, "}")
		}
		gline(&b, 1, "}")
		gline(&b, 0, "")
		emit_product_flavors(&b, target)
		if target.android.view_binding || target.android.compose || target.android.build_config || len(target.android.build_config_fields) > 0 {
			gline(&b, 1, "buildFeatures {")
			if target.android.view_binding do gline(&b, 2, "viewBinding true")
			if target.android.compose do gline(&b, 2, "compose true")
			if target.android.build_config || len(target.android.build_config_fields) > 0 do gline(&b, 2, "buildConfig true")
			gline(&b, 1, "}")
		}
		gline(&b, 1, "compileOptions {")
		gline(&b, 2, "sourceCompatibility JavaVersion.VERSION_17")
		gline(&b, 2, "targetCompatibility JavaVersion.VERSION_17")
		gline(&b, 1, "}")
		if use_kotlin {
			gline(&b, 1, "kotlinOptions { jvmTarget = '17' }")
		}
		gline(&b, 1, "sourceSets {")
		gline(&b, 2, "main {")
		gline(&b, 3, "java.srcDirs += 'src/main/kotlin'")
		if target.android.native_build.present {
			gline(&b, 3, fmt.tprintf("jniLibs.srcDirs += project.file(%s)", gq(native_output_dir(project, target, module_dir))))
		}
		gline(&b, 2, "}")
		gline(&b, 1, "}")
		gline(&b, 0, "}")
	}

	emit_native_build(&b, project, target, module_dir)

	// Dependencies
	gline(&b, 0, "")
	gline(&b, 0, "dependencies {")
	for dep in target.dependencies {
		line := dependency_line(project, target, dep)
		if line != "" do gline(&b, 1, line)
	}
	gline(&b, 0, "}")
	emit_scripts(&b, project, target, module_dir)
	return strings.to_string(b)
}

external_kind_name :: proc(kind: External_Native_Kind) -> string {
	switch kind {
	case .CMake: return "cmake"
	case .NdkBuild: return "ndkBuild"
	case .None: return ""
	}
	return ""
}

emit_signing_configs :: proc(b: ^strings.Builder, project: ^Project, target: ^Target) {
	if len(target.android.signing_configs) == 0 do return
	gline(b, 1, "signingConfigs {")
	for sc in target.android.signing_configs {
		gline(b, 2, strings.concatenate([]string{sc.name, " {"}))
		if sc.store_file != "" {
			path := sc.store_file
			if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
			gline(b, 3, fmt.tprintf("storeFile file(%s)", gq(path)))
		}
		if sc.store_password_env != "" {
			gline(b, 3, fmt.tprintf("storePassword System.getenv(%s)", gq(sc.store_password_env)))
		} else if sc.store_password != "" {
			gline(b, 3, fmt.tprintf("storePassword %s", gq(sc.store_password)))
		}
		if sc.key_alias != "" do gline(b, 3, fmt.tprintf("keyAlias %s", gq(sc.key_alias)))
		if sc.key_password_env != "" {
			gline(b, 3, fmt.tprintf("keyPassword System.getenv(%s)", gq(sc.key_password_env)))
		} else if sc.key_password != "" {
			gline(b, 3, fmt.tprintf("keyPassword %s", gq(sc.key_password)))
		}
		if sc.store_type != "" do gline(b, 3, fmt.tprintf("storeType %s", gq(sc.store_type)))
		gline(b, 2, "}")
	}
	gline(b, 1, "}")
	gline(b, 0, "")
}

emit_product_flavors :: proc(b: ^strings.Builder, target: ^Target) {
	if len(target.android.flavors) == 0 do return
	if len(target.android.flavor_dimensions) > 0 {
		line_parts := make([dynamic]string)
		for dim in target.android.flavor_dimensions do append(&line_parts, gq(dim))
		gline(b, 1, fmt.tprintf("flavorDimensions %s", strings.join(line_parts[:], ", ")))
	}
	gline(b, 1, "productFlavors {")
	for f in target.android.flavors {
		gline(b, 2, strings.concatenate([]string{f.name, " {"}))
		if f.dimension != "" do gline(b, 3, fmt.tprintf("dimension %s", gq(f.dimension)))
		if f.application_id_suffix != "" do gline(b, 3, fmt.tprintf("applicationIdSuffix %s", gq(f.application_id_suffix)))
		if f.version_name_suffix != "" do gline(b, 3, fmt.tprintf("versionNameSuffix %s", gq(f.version_name_suffix)))
		if f.min_sdk > 0 do gline(b, 3, fmt.tprintf("minSdk %d", f.min_sdk))
		if f.target_sdk > 0 do gline(b, 3, fmt.tprintf("targetSdk %d", f.target_sdk))
		gline(b, 2, "}")
	}
	gline(b, 1, "}")
	gline(b, 0, "")
}

emit_external_native_android :: proc(b: ^strings.Builder, project: ^Project, target: ^Target) {
	e := target.android.external
	if !e.present do return
	path := e.path
	if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
	kind := external_kind_name(e.kind)
	if kind == "" do return
	gline(b, 1, "externalNativeBuild {")
	gline(b, 2, strings.concatenate([]string{kind, " {"}))
	gline(b, 3, fmt.tprintf("path project.file(%s)", gq(path)))
	if kind == "cmake" && e.version != "" do gline(b, 3, fmt.tprintf("version %s", gq(e.version)))
	gline(b, 2, "}")
	gline(b, 1, "}")
}

emit_external_native_default :: proc(b: ^strings.Builder, project: ^Project, target: ^Target) {
	e := target.android.external
	if !e.present do return
	kind := external_kind_name(e.kind)
	if kind == "" do return
	if len(e.arguments) == 0 && len(e.c_flags) == 0 && len(e.cpp_flags) == 0 && len(e.targets) == 0 do return
	gline(b, 2, "externalNativeBuild {")
	gline(b, 3, strings.concatenate([]string{kind, " {"}))
	if len(e.arguments) > 0 do gline(b, 4, fmt.tprintf("arguments %s", groovy_string_list(e.arguments)))
	if kind == "cmake" {
		if len(e.c_flags) > 0 do gline(b, 4, fmt.tprintf("cFlags %s", groovy_string_list(e.c_flags)))
		if len(e.cpp_flags) > 0 do gline(b, 4, fmt.tprintf("cppFlags %s", groovy_string_list(e.cpp_flags)))
		if len(e.targets) > 0 do gline(b, 4, fmt.tprintf("targets %s", groovy_string_list(e.targets)))
	}
	gline(b, 3, "}")
	gline(b, 2, "}")
}

groovy_string_list :: proc(values: []string) -> string {
	parts := make([dynamic]string)
	for v in values do append(&parts, gq(v))
	return strings.join(parts[:], ", ")
}

native_output_dir :: proc(project: ^Project, target: ^Target, module_dir: string) -> string {
	path := target.android.native_build.output
	if path == "" do return join_path(module_dir, "build/generated/native")
	if !filepath.is_abs(path) do path = join_path(module_dir, path)
	return clean_path(path)
}

emit_native_build :: proc(b: ^strings.Builder, project: ^Project, target: ^Target, module_dir: string) {
	nb := target.android.native_build
	if !nb.present do return
	out_dir := native_output_dir(project, target, module_dir)
	command := nb.command
	if !filepath.is_abs(command) do command = join_path(project.base_dir, command)
	gline(b, 0, "")
	gline(b, 0, fmt.tprintf("def androidgenNativeAbis = [%s]", groovy_string_list(nb.abis)))
	gline(b, 0, "androidgenNativeAbis.each { abi ->")
	gline(b, 1, "def taskName = 'androidgenNative_' + abi.replace('-', '_')")
	gline(b, 1, "tasks.register(taskName, Exec) {")
	gline(b, 2, fmt.tprintf("workingDir project.file(%s)", gq(project.base_dir)))
	gline(b, 2, "environment 'ANDROID_ABI', abi")
	gline(b, 2, "environment 'ANDROID_NDK', android.ndkDirectory.absolutePath")
	gline(b, 2, "environment 'ANDROID_NDK_HOME', android.ndkDirectory.absolutePath")
	gline(b, 2, "environment 'ANDROID_PLATFORM', \"android-\" + android.defaultConfig.minSdk")
	gline(b, 2, fmt.tprintf("environment 'ANDROIDGEN_NATIVE_OUT', project.file(%s).absolutePath", gq(out_dir)))
	gline(b, 2, fmt.tprintf("environment 'ANDROIDGEN_PROJECT_ROOT', project.file(%s).absolutePath", gq(project.base_dir)))
	for k in sorted_string_map_keys(nb.env) {
		gline(b, 2, fmt.tprintf("environment %s, %s", gq(k), gq(nb.env[k])))
	}
	gline(b, 2, fmt.tprintf("commandLine 'sh', project.file(%s).absolutePath", gq(command)))
	if len(nb.args) > 0 {
		gline(b, 2, fmt.tprintf("args %s", groovy_string_list(nb.args)))
	}
	if len(nb.inputs) > 0 {
		for input in nb.inputs {
			path := input
			if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
			if os.is_dir(path) {
				gline(b, 2, fmt.tprintf("inputs.dir project.file(%s)", gq(path)))
			} else {
				gline(b, 2, fmt.tprintf("inputs.file project.file(%s)", gq(path)))
			}
		}
	} else {
		gline(b, 2, "outputs.upToDateWhen { false }")
	}
	gline(b, 2, fmt.tprintf("outputs.dir project.file(%s + '/' + abi)", gq(out_dir)))
	gline(b, 1, "}")
	gline(b, 1, "preBuild.dependsOn taskName")
	gline(b, 0, "}")
}

bool_gradle :: proc(v: bool) -> string {
	return "true" if v else "false"
}

field_for_config :: proc(configs: []string, display, name: string) -> bool {
	if len(configs) == 0 do return true
	for c in configs {
		if strings.equal_fold(c, display) || strings.equal_fold(c, name) do return true
	}
	return false
}

dependency_line :: proc(project: ^Project, target: ^Target, dep: Dependency) -> string {
	config := dep.configuration
	if config == "" {
		if !dep.link {
			config = "runtimeOnly"
		} else if !dep.embed {
			config = "compileOnly"
		} else if dep.weak {
			config = "compileOnly"
		} else {
			config = "implementation"
		}
	}
	switch dep.kind {
	case .Target:
		other := find_target(project, dep.name)
		if other == nil do return ""
		return fmt.tprintf("%s project(%s)", config, gq(strings.concatenate([]string{":", other.module_name})))
	case .Framework:
		path := dep.path
		if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
		return fmt.tprintf("%s files(%s)", config, gq(path))
	case .Package:
		pkg, ok := project.packages[dep.name]
		if !ok do return ""
		artifact := pkg.artifact
		if dep.product != "" do artifact = dep.product
		if len(dep.products) > 0 {
			lines := make([dynamic]string)
			for product in dep.products {
				append(&lines, fmt.tprintf("%s %s", config, gq(strings.concatenate([]string{pkg.group, ":", product, ":", pkg.version}))))
			}
			return strings.join(lines[:], "\n    ")
		}
		coord := strings.concatenate([]string{pkg.group, ":", artifact, ":", pkg.version})
		return fmt.tprintf("%s %s", config, gq(coord))
	case .Maven:
		return fmt.tprintf("%s %s", config, gq(dep.name))
	case .Unsupported:
		return ""
	}
	return ""
}

script_task_name :: proc(target: ^Target, phase: string, index: int) -> string {
	return fmt.tprintf("androidgen_%s_%s_%d", target.module_name, phase, index)
}

emit_scripts :: proc(b: ^strings.Builder, project: ^Project, target: ^Target, module_dir: string) {
	emit_script_list(b, project, target, module_dir, target.pre_scripts, "pre", "preBuild.dependsOn")
	emit_script_list(b, project, target, module_dir, target.post_compile_scripts, "postcompile", "")
	emit_script_list(b, project, target, module_dir, target.post_scripts, "post", "assemble.finalizedBy")
}

emit_script_list :: proc(b: ^strings.Builder, project: ^Project, target: ^Target, module_dir: string, scripts: []Script, phase, wire: string) {
	if len(scripts) == 0 do return
	gline(b, 0, "")
	for script, i in scripts {
		task := script_task_name(target, phase, i)
		script_dir := join_path(module_dir, "androidgen-scripts")
		os.mkdir_all(script_dir)
		script_path := join_path(script_dir, fmt.tprintf("%s.sh", task))
		content := script.script
		if content == "" && script.path != "" {
			path := script.path
			if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
			content = strings.concatenate([]string{"#!/bin/sh\nexec ", shell_quote(path), " \"$@\"\n"})
		}
		if content == "" do continue
		if !strings.has_prefix(content, "#!") {
			content = strings.concatenate([]string{"#!/bin/sh\n", content})
		}
		_ = os.write_entire_file_from_string(script_path, content)
		gline(b, 0, fmt.tprintf("tasks.register(%s, Exec) %s", gq(task), "{"))
		gline(b, 1, "workingDir rootProject.projectDir")
		shell := script.shell
		if shell == "" do shell = "/bin/sh"
		gline(b, 1, fmt.tprintf("commandLine %s, file(%s).absolutePath", gq(shell), gq(script_path)))
		if len(script.input_files) > 0 {
			gline(b, 1, fmt.tprintf("inputs.files(%s)", groovy_file_list(project.base_dir, script.input_files)))
		}
		if len(script.output_files) > 0 {
			gline(b, 1, fmt.tprintf("outputs.files(%s)", groovy_file_list(project.base_dir, script.output_files)))
		}
		if !script.based_on_dependency_analysis {
			gline(b, 1, "outputs.upToDateWhen { false }")
		}
		gline(b, 0, "}")
		switch phase {
		case "pre":
			gline(b, 0, fmt.tprintf("preBuild.dependsOn %s", gq(task)))
		case "postcompile":
			gline(b, 0, fmt.tprintf("tasks.matching %s it.name.startsWith('compile') %s.configureEach %s finalizedBy %s %s", "{", "}", "{", gq(task), "}"))
		case "post":
			gline(b, 0, fmt.tprintf("assemble.finalizedBy %s", gq(task)))
		}
	}
	_ = wire
}

groovy_file_list :: proc(base_dir: string, paths: []string) -> string {
	parts := make([dynamic]string)
	for p in paths {
		path := p
		if !filepath.is_abs(path) do path = join_path(base_dir, path)
		append(&parts, fmt.tprintf("file(%s)", gq(path)))
	}
	return strings.join(parts[:], ", ")
}

shell_quote :: proc(s: string) -> string {
	escaped, _ := strings.replace_all(s, "'", "'\\''")
	return strings.concatenate([]string{"'", escaped, "'"})
}
