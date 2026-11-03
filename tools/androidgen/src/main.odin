package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

VERSION :: "0.3.0"

Cli_Options :: struct {
	spec:           string,
	project:        string,
	project_root:   string,
	platform:       string,
	quiet:          bool,
	no_env:         bool,
	use_cache:      bool,
	cache_path:     string,
	only_manifests: bool,
	templates:      string,
	dry_run:        bool,
	keep_going:     bool,
}

usage :: proc() {
	fmt.println("androidgen", VERSION, "- generate Android Gradle projects from a project spec")
	fmt.println()
	fmt.println("usage:")
	fmt.println("  androidgen generate [options]")
	fmt.println("  androidgen cache [options]")
	fmt.println("  androidgen dump [options]")
	fmt.println("  androidgen check [project.yaml]")
	fmt.println("  androidgen platforms [project.yaml]")
	fmt.println()
	fmt.println("options:")
	fmt.println("  -s, --spec <path>          project spec (default: project.yml)")
	fmt.println("  -p, --project <dir>        output project directory")
	fmt.println("      --project-root <dir>   root for resolving spec paths")
	fmt.println("      --platform <name|all>  generate a platform from project.yaml")
	fmt.println("  -q, --quiet                suppress informational output")
	fmt.println("  -n, --no-env               disable ${ENV} expansion")
	fmt.println("  -c, --use-cache            skip generation when the spec is unchanged")
	fmt.println("      --cache-path <path>    custom cache file")
	fmt.println("      --only-manifests       write generated manifests only")
	fmt.println("      --templates <dir>      custom template/wrapper asset directory")
	fmt.println("      --dry-run              print orchestrator commands only")
	fmt.println("      --keep-going           continue after a platform fails")
	fmt.println("      --version              print version")
	fmt.println("  -h, --help                 show this help")
}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		run_generate_command(Cli_Options{})
		return
	}
	switch args[1] {
	case "generate", "gen":
		opts := parse_cli(args[2:])
		run_generate_command(opts)
	case "cache":
		opts := parse_cli(args[2:])
		run_cache_command(opts)
	case "dump":
		run_dump_command(args[2:])
	case "check":
		run_check_command(args[2:])
	case "platforms":
		run_platforms_command(args[2:])
	case "--version", "version":
		fmt.println(VERSION)
	case "--help", "-h", "help":
		usage()
	case:
		// XcodeGen routes unknown invocations to generate. Mirror that.
		if strings.has_prefix(args[1], "-") {
			opts := parse_cli(args[1:])
			run_generate_command(opts)
		} else {
			fmt.eprintln("androidgen: unknown command:", args[1])
			usage()
			os.exit(1)
		}
	}
}

parse_cli :: proc(args: []string) -> Cli_Options {
	opts := Cli_Options{}
	i := 0
	for i < len(args) {
		a := args[i]
		next_value :: proc(args: []string, i: ^int, flag: string) -> string {
			if i^ + 1 >= len(args) {
				fmt.eprintln("androidgen: missing value for", flag)
				os.exit(1)
			}
			i^ += 1
			return args[i^]
		}
		switch a {
		case "-s", "--spec":
			opts.spec = next_value(args, &i, a)
		case "-p", "--project", "--out":
			opts.project = next_value(args, &i, a)
		case "-r", "--project-root":
			opts.project_root = next_value(args, &i, a)
		case "--platform":
			opts.platform = next_value(args, &i, a)
		case "-q", "--quiet":
			opts.quiet = true
		case "-n", "--no-env":
			opts.no_env = true
		case "-c", "--use-cache":
			opts.use_cache = true
		case "--cache-path":
			opts.cache_path = next_value(args, &i, a)
		case "--only-manifests", "--only-plists":
			opts.only_manifests = true
		case "--templates":
			opts.templates = next_value(args, &i, a)
		case "--dry-run":
			opts.dry_run = true
		case "--keep-going":
			opts.keep_going = true
		case "--version":
			fmt.println(VERSION)
			os.exit(0)
		case "-h", "--help":
			usage()
			os.exit(0)
		case:
			fmt.eprintln("androidgen: unknown argument:", a)
			os.exit(1)
		}
		i += 1
	}
	return opts
}

run_generate_command :: proc(opts_in: Cli_Options) {
	opts := opts_in
	if opts.platform != "" {
		run_platform_command(opts)
		return
	}

	// If no explicit spec was provided and a cross-platform manifest exists,
	// route through it. This makes `androidgen generate` work in a repo that
	// has project.yaml + android.yaml + ios.yaml.
	if opts.spec == "" && file_exists("project.yaml") && !file_exists("project.yml") {
		if looks_like_manifest("project.yaml") {
			manifest, err := load_manifest("project.yaml")
			if err != "" {
				fmt.eprintln("androidgen:", err)
				os.exit(1)
			}
			opts.platform = manifest.default_platform
			if opts.platform == "" do opts.platform = "android"
			run_platform_command(opts)
			return
		}
		opts.spec = "project.yaml"
	}

	spec := opts.spec
	if spec == "" do spec = "project.yml"
	if !file_exists(spec) {
		fmt.eprintln("androidgen: spec not found:", spec)
		os.exit(1)
	}
	err := generate_project(spec, opts.project, opts.project_root, opts)
	if err != "" {
		fmt.eprintln("androidgen:", err)
		os.exit(1)
	}
}

run_cache_command :: proc(opts: Cli_Options) {
	spec := opts.spec
	if spec == "" {
		if file_exists("project.yml") {
			spec = "project.yml"
		} else if file_exists("project.yaml") && !looks_like_manifest("project.yaml") {
			spec = "project.yaml"
		} else {
			spec = "project.yml"
		}
	}
	if !file_exists(spec) {
		fmt.eprintln("androidgen: spec not found:", spec)
		os.exit(1)
	}
	err := write_cache_for_spec(spec, opts.project_root, opts.no_env, opts.cache_path, opts.quiet)
	if err != "" {
		fmt.eprintln("androidgen:", err)
		os.exit(1)
	}
}

run_dump_command :: proc(args: []string) {
	spec := ""
	project_root := ""
	dump_type := "yaml"
	out_file := ""
	no_env := false
	i := 0
	for i < len(args) {
		switch args[i] {
		case "-s", "--spec":
			i += 1
			spec = args[i]
		case "-r", "--project-root":
			i += 1
			project_root = args[i]
		case "-t", "--type":
			i += 1
			dump_type = args[i]
		case "-f", "--file":
			i += 1
			out_file = args[i]
		case "-n", "--no-env":
			no_env = true
		case "-q", "--quiet":
			// dump output is the payload; quiet has no effect
		case:
			fmt.eprintln("androidgen dump: unknown argument:", args[i])
			os.exit(1)
		}
		i += 1
	}
	if spec == "" {
		if file_exists("project.yml") {
			spec = "project.yml"
		} else if file_exists("project.yaml") {
			spec = "project.yaml"
		} else {
			spec = "project.yml"
		}
	}
	value: Value
	if is_legacy_file(spec) {
		project, _, legacy_err := load_legacy_project(spec, project_root, "")
		if legacy_err != "" {
			fmt.eprintln("androidgen:", legacy_err)
			os.exit(1)
		}
		value = project.raw
	} else {
		loaded, err := load_spec_opts(spec, project_root, no_env)
		if err != "" {
			fmt.eprintln("androidgen:", err)
			os.exit(1)
		}
		value = resolve_target_templates(loaded.value)
	}
	output: string
	switch dump_type {
	case "yaml", "parsed-yaml":
		output = yaml_dump_value(value)
	case "json", "parsed-json":
		output = json_dump_value(value)
	case "summary":
		output = dump_summary(value)
	case:
		fmt.eprintln("androidgen dump: unknown type:", dump_type)
		os.exit(1)
	}
	if out_file != "" {
		parent := filepath.dir(out_file)
		if parent != "" do os.mkdir_all(parent)
		if os.write_entire_file_from_string(out_file, output) != nil {
			fmt.eprintln("androidgen: cannot write", out_file)
			os.exit(1)
		}
	} else {
		fmt.print(output)
	}
}

dump_summary :: proc(v: Value) -> string {
	m, _ := v.(Map)
	out := fmt.tprintf("Name: %s\n", m_get_string(m, "name"))
	if targets, has := m_get(m, "targets"); has {
		if tm, ok := targets.(Map); ok {
			out = strings.concatenate([]string{out, "Targets:\n"})
			for key in tm.keys {
				t, _ := tm.values[key].(Map)
				out = strings.concatenate([]string{out, fmt.tprintf("  %s: %s %s\n", key, m_get_string(t, "platform"), m_get_string(t, "type"))})
			}
		}
	}
	if configs, has := m_get(m, "configs"); has {
		if cm, ok := configs.(Map); ok {
			out = strings.concatenate([]string{out, "Configs:\n"})
			for key in cm.keys {
				out = strings.concatenate([]string{out, fmt.tprintf("  %s: %s\n", key, value_string(cm.values[key]))})
			}
		}
	}
	return out
}

run_platforms_command :: proc(args: []string) {
	manifest_path := "project.yaml"
	if len(args) > 0 do manifest_path = args[0]
	manifest, err := load_manifest(manifest_path)
	if err != "" {
		fmt.eprintln("androidgen:", err)
		os.exit(1)
	}
	fmt.println("Project:", manifest.name)
	for p in manifest.platforms {
		status := "available"
		if p.generator == "xcodegen" && !command_exists("xcodegen") do status = "xcodegen not found"
		fmt.printf("  %-10s %-12s %-30s %s\n", p.name, p.generator, p.spec, status)
	}
}

run_check_command :: proc(args: []string) {
	manifest_path := "project.yaml"
	if len(args) > 0 do manifest_path = args[0]
	err := check_manifest(manifest_path)
	if err != "" {
		fmt.eprintln("androidgen: coherence check failed")
		fmt.eprintln(err)
		os.exit(1)
	}
	fmt.println("androidgen: coherence check passed")
}

run_platform_command :: proc(opts: Cli_Options) {
	manifest_path := "project.yaml"
	manifest, err := load_manifest(manifest_path)
	if err != "" {
		fmt.eprintln("androidgen:", err)
		os.exit(1)
	}
	selected := opts.platform
	if selected == "" do selected = manifest.default_platform
	if selected == "" do selected = "android"
	failed := false
	ran := false
	for p in manifest.platforms {
		if !strings.equal_fold(selected, "all") && !strings.equal_fold(selected, p.name) do continue
		ran = true
		if !p.enabled {
			if !opts.quiet do fmt.println("androidgen:", p.name, "is disabled")
			continue
		}
		ok := run_platform(manifest, p, opts)
		if !ok {
			failed = true
			if !opts.keep_going do break
		}
	}
	if !ran {
		fmt.eprintln("androidgen: no platform named", selected)
		os.exit(1)
	}
	if failed do os.exit(1)
}

run_platform :: proc(manifest: Manifest, p: Platform_Entry, opts: Cli_Options) -> bool {
	spec := p.spec
	project := p.project
	root := p.project_root
	if root == "" do root = manifest.root
	if opts.project != "" do project = opts.project
	if opts.project_root != "" do root = opts.project_root
	if !filepath.is_abs(spec) do spec = join_path(manifest.root, spec)
	if opts.project != "" {
		if abs_out, err := filepath.abs(project); err == nil do project = abs_out
	} else if !filepath.is_abs(project) {
		project = join_path(manifest.root, project)
	}
	if !filepath.is_abs(root) do root = join_path(manifest.root, root)

	if p.generator == "androidgen" {
		if opts.dry_run {
			fmt.println(strings.join([]string{"androidgen", "generate", "--spec", spec, "--project", project, "--project-root", root}, " "))
			return true
		}
		child := opts
		child.platform = ""
		child.spec = spec
		child.project = project
		child.project_root = root
		for arg in p.args {
			if arg == "--use-cache" do child.use_cache = true
			if arg == "--quiet" do child.quiet = true
		}
		err := generate_project(spec, project, root, child)
		if err != "" {
			fmt.eprintln("androidgen:", err)
			return false
		}
		return true
	}

	if p.generator == "xcodegen" {
		command := make([dynamic]string)
		append(&command, "xcodegen", "generate", "--spec", spec, "--project", project, "--project-root", root)
		if opts.quiet do append(&command, "--quiet")
		if opts.use_cache do append(&command, "--use-cache")
		if opts.no_env do append(&command, "--no-env")
		for arg in p.args do append(&command, arg)
		if opts.dry_run {
			fmt.println(strings.join(command[:], " "))
			return true
		}
		if !command_exists("xcodegen") {
			fmt.eprintln("androidgen: xcodegen not found (iOS generation requires macOS + XcodeGen)")
			return false
		}
		os.mkdir_all(project)
		return run_process(command[:], manifest.root)
	}

	// Custom generator: run the command template.
	if p.command != "" {
		cmd := p.command
		cmd, _ = strings.replace_all(cmd, "{spec}", spec)
		cmd, _ = strings.replace_all(cmd, "{project}", project)
		cmd, _ = strings.replace_all(cmd, "{root}", root)
		cmd, _ = strings.replace_all(cmd, "{name}", manifest.name)
		if opts.dry_run {
			fmt.println(cmd)
			return true
		}
		return run_shell(cmd, manifest.root)
	}
	fmt.eprintln("androidgen: unknown generator", p.generator)
	return false
}

run_process :: proc(args: []string, working_dir: string) -> bool {
	desc := os.Process_Desc {
		command     = args,
		working_dir = working_dir,
	}
	state, stdout, stderr, err := os.process_exec(desc, context.allocator)
	if err != nil {
		fmt.eprintln("androidgen: failed to run", strings.join(args, " "), ":", err)
		return false
	}
	if len(stdout) > 0 do fmt.print(string(stdout))
	if len(stderr) > 0 do fmt.eprint(string(stderr))
	return state.success
}

run_shell :: proc(command, working_dir: string) -> bool {
	return run_process([]string{"sh", "-c", command}, working_dir)
}

command_exists :: proc(name: string) -> bool {
	state, _, _, err := os.process_exec(os.Process_Desc{command = []string{"sh", "-c", strings.concatenate([]string{"command -v ", name})}}, context.allocator)
	return err == nil && state.success
}

file_exists :: proc(path: string) -> bool {
	return os.is_file(path)
}
