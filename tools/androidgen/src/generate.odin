package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"

generate_project :: proc(spec_path, output_override, project_root: string, opts: Cli_Options) -> string {
	project, loaded, err := load_and_parse_project(spec_path, project_root, output_override, opts.no_env)
	if err != "" do return err

	out_dir := ""
	if output_override != "" {
		if filepath.is_abs(output_override) {
			out_dir = output_override
		} else if abs_out, abs_err := filepath.abs(output_override); abs_err == nil {
			out_dir = abs_out
		} else {
			out_dir = output_override
		}
	} else {
		out_dir = project.output_dir
		if !filepath.is_abs(out_dir) do out_dir = join_path(project.base_dir, out_dir)
	}
	out_dir = clean_path(out_dir)

	if project.options.pre_gen_command != "" {
		if !opts.quiet do fmt.println("androidgen: running preGenCommand")
		if !run_shell(project.options.pre_gen_command, project.base_dir) {
			return fmt.tprintf("preGenCommand failed: %s", project.options.pre_gen_command)
		}
	}
	if err := generate_bindings(&project); err != "" do return err
	if !opts.quiet && len(project.bindings) > 0 {
		fmt.println("androidgen: generated", len(project.bindings), "binding set(s)")
	}

	cache_path := opts.cache_path
	if cache_path == "" do cache_path = default_cache_path(loaded.path)
	if opts.use_cache {
		if cache_matches(&project, loaded, cache_path) && os.is_file(join_path(out_dir, "settings.gradle")) {
			if !opts.quiet do fmt.println("androidgen:", project.name, "has not changed since cache was written")
			return ""
		}
	}

	if !opts.quiet {
		for warning in project.warnings do fmt.println("androidgen: warning:", warning)
	}

	tool_dir := opts.templates
	if tool_dir == "" {
		bin := os.args[0]
		abs_bin, abs_err := filepath.abs(bin)
		if abs_err == nil do tool_dir = filepath.dir(abs_bin)
	}
	if tool_dir == "" do tool_dir = "."
	if !os.is_file(join_path(tool_dir, "wrapper/gradlew")) {
		parent := filepath.dir(tool_dir)
		if os.is_file(join_path(parent, "wrapper/gradlew")) do tool_dir = parent
	}

	if opts.only_manifests {
		for &t in project.targets {
			module_dir := join_path(out_dir, t.module_name)
			src_main := join_path(module_dir, "src/main")
			os.mkdir_all(src_main)
			if err := write_target_manifest(&project, &t, module_dir, Source_Result{}); err != "" do return err
		}
		return ""
	}

	os.mkdir_all(out_dir)
	for &t in project.targets {
		module_dir := join_path(out_dir, t.module_name)
		src_main := join_path(module_dir, "src/main")
		os.mkdir_all(module_dir)
		if os.is_dir(src_main) do _ = os.remove_all(src_main)
		scripts_dir := join_path(module_dir, "androidgen-scripts")
		if os.is_dir(scripts_dir) do _ = os.remove_all(scripts_dir)
		proguard_link := join_path(module_dir, "proguard-rules.pro")
		if fi, stat_err := os.stat_do_not_follow_links(proguard_link, context.allocator); stat_err == nil {
			os.file_info_delete(fi, context.allocator)
			_ = os.remove(proguard_link)
		}

		src_result, src_err := build_sources(&project, &t, module_dir)
		if src_err != "" do return src_err
		if err := write_target_manifest(&project, &t, module_dir, src_result); err != "" do return err
		if len(src_result.proguard) > 0 {
			t.android.proguard_files = src_result.proguard[:]
		}
		gradle := emit_module_gradle(&project, &t, module_dir)
		if err := write_text_file(join_path(module_dir, "build.gradle"), gradle); err != "" do return err
	}

	if err := write_text_file(join_path(out_dir, "settings.gradle"), emit_root_gradle(&project)); err != "" do return err
	if err := write_text_file(join_path(out_dir, "build.gradle"), emit_root_build_gradle(&project)); err != "" do return err
	if err := write_text_file(join_path(out_dir, "gradle.properties"), emit_gradle_properties(&project)); err != "" do return err
	if err := write_text_file(join_path(out_dir, "gradle/wrapper/gradle-wrapper.properties"), emit_wrapper_properties(&project)); err != "" do return err

	if err := copy_wrapper(tool_dir, out_dir); err != "" do return err
	write_cache(&project, loaded, cache_path)

	if project.options.post_gen_command != "" {
		if !opts.quiet do fmt.println("androidgen: running postGenCommand")
		if !run_shell(project.options.post_gen_command, project.base_dir) {
			return fmt.tprintf("postGenCommand failed: %s", project.options.post_gen_command)
		}
	}

	if !opts.quiet {
		fmt.println("androidgen: generated", out_dir)
		fmt.println("  project:", project.name)
		fmt.println("  targets:", len(project.targets))
		fmt.println("  gradle", project.options.android.gradle_version, "+ agp", project.options.android.agp_version)
		fmt.println("build with: cd", out_dir, "&& ./gradlew assembleDebug")
	}
	return ""
}

copy_wrapper :: proc(tool_dir, out_dir: string) -> string {
	gradlew_src := join_path(tool_dir, "wrapper/gradlew")
	bat_src := join_path(tool_dir, "wrapper/gradlew.bat")
	jar_src := join_path(tool_dir, "wrapper/gradle/wrapper/gradle-wrapper.jar")
	if !os.is_file(gradlew_src) || !os.is_file(jar_src) {
		return fmt.tprintf("missing gradle wrapper assets under %s (use --templates <dir>)", tool_dir)
	}
	if err := os.copy_file(join_path(out_dir, "gradlew"), gradlew_src); err != nil {
		return fmt.tprintf("cannot copy gradlew")
	}
	if os.is_file(bat_src) {
		_ = os.copy_file(join_path(out_dir, "gradlew.bat"), bat_src)
	}
	_ = os.mkdir_all(join_path(out_dir, "gradle/wrapper"))
	if err := os.copy_file(join_path(out_dir, "gradle/wrapper/gradle-wrapper.jar"), jar_src); err != nil {
		return fmt.tprintf("cannot copy gradle-wrapper.jar")
	}
	return ""
}
