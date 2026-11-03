package odinbinder

import "core:fmt"
import "core:os"
import "core:strings"

Options :: struct {
	target: string,
	spec:   string,
	header: string,
	kotlin: string,
	jni:    string,
	swift:  string,
	quiet:  bool,
	check:  bool,
}

usage :: proc() {
	fmt.println("odinbinder - generate Odin <-> Android/iOS bindings from Odin proc declarations")
	fmt.println()
	fmt.println("usage:")
	fmt.println("  odinbinder generate --target android|ios|all --spec <dir|file> [outputs]")
	fmt.println("  odinbinder check --spec <dir|file>")
	fmt.println()
	fmt.println("outputs:")
	fmt.println("  --header <path>   C ABI header")
	fmt.println("  --kotlin <path>   Android Kotlin bridge")
	fmt.println("  --jni <path>      Android JNI glue")
	fmt.println("  --swift <path>    iOS Swift bridge")
}

main :: proc() {
	if len(os.args) < 2 {
		usage()
		os.exit(1)
	}
	opts := parse_args(os.args[1:])
	if opts.spec == "" {
		fmt.eprintln("odinbinder: --spec is required")
		os.exit(1)
	}
	if opts.check {
		if err := check_spec(opts); err != "" {
			fmt.eprintln("odinbinder:", err)
			os.exit(1)
		}
		if !opts.quiet do fmt.println("odinbinder: spec is valid")
		return
	}
	if err := generate(opts); err != "" {
		fmt.eprintln("odinbinder:", err)
		os.exit(1)
	}
}

parse_args :: proc(args: []string) -> Options {
	opts := Options{}
	i := 0
	if len(args) > 0 && args[0] == "check" {
		opts.check = true
		i = 1
	} else if len(args) > 0 && args[0] == "generate" {
		i = 1
	}
	next :: proc(args: []string, i: ^int, flag: string) -> string {
		if i^ + 1 >= len(args) {
			fmt.eprintln("odinbinder: missing value for", flag)
			os.exit(1)
		}
		i^ += 1
		return args[i^]
	}
	for i < len(args) {
		switch args[i] {
		case "--target":
			opts.target = next(args, &i, args[i])
		case "--spec":
			opts.spec = next(args, &i, args[i])
		case "--header":
			opts.header = next(args, &i, args[i])
		case "--kotlin":
			opts.kotlin = next(args, &i, args[i])
		case "--jni":
			opts.jni = next(args, &i, args[i])
		case "--swift":
			opts.swift = next(args, &i, args[i])
		case "-q", "--quiet":
			opts.quiet = true
		case "-h", "--help":
			usage()
			os.exit(0)
		case:
			fmt.eprintln("odinbinder: unknown argument", args[i])
			os.exit(1)
		}
		i += 1
	}
	if opts.target == "" do opts.target = "android"
	return opts
}

parse_target_name :: proc(name: string) -> (Target, bool) {
	switch strings.to_lower(name) {
	case "android":
		return .Android, true
	case "ios":
		return .Ios, true
	}
	return .Android, false
}

load_module :: proc(spec: string) -> (Module, string) {
	info, err := os.stat(spec, context.allocator)
	if err != nil do return {}, fmt.tprintf("cannot stat spec: %s", spec)
	is_dir := info.type == .Directory
	os.file_info_delete(info, context.allocator)
	path := spec
	if is_dir {
		path = join_path(spec, "binding.odin")
		if !os.is_file(path) do return {}, fmt.tprintf("no binding.odin in %s", spec)
	}
	module, parse_err := parse_binding_file(path)
	if parse_err != "" do return {}, parse_err
	fill_module_defaults(&module)
	return module, ""
}

fill_module_defaults :: proc(m: ^Module) {
	if m.name == "" do m.name = "binding"
	if m.android_pkg == "" do m.android_pkg = "com.example"
	if m.android_class == "" do m.android_class = "Bridge"
	if m.ios_module == "" do m.ios_module = "Bridge"
}

check_spec :: proc(opts: Options) -> string {
	if !strings.equal_fold(opts.target, "all") {
		if _, ok := parse_target_name(opts.target); !ok {
			return fmt.tprintf("unknown target %q", opts.target)
		}
	}
	module, err := load_module(opts.spec)
	if err != "" do return err
	return validate_module(module)
}

generate :: proc(opts: Options) -> string {
	module, err := load_module(opts.spec)
	if err != "" do return err
	if verr := validate_module(module); verr != "" do return verr

	if opts.header != "" {
		if e := emit_header(module, opts.header); e != "" do return e
	}

	if strings.equal_fold(opts.target, "all") {
		for t in ([]Target{.Android, .Ios}) {
			if e := emit_platform(module, t, opts); e != "" do return e
		}
		return ""
	}

	target, ok := parse_target_name(opts.target)
	if !ok do return fmt.tprintf("unknown target %q", opts.target)
	return emit_platform(module, target, opts)
}

validate_module :: proc(module: Module) -> string {
	for f, i in module.functions {
		if f.direction == .Import && (f.ret == "cstring" || is_nullable_cstring(f.ret)) {
			return fmt.tprintf("%s: import %s cannot return cstring", module.name, f.name)
		}
		for g, j in module.functions {
			if i != j && f.name == g.name {
				return fmt.tprintf("%s: duplicate declaration %s", module.name, f.name)
			}
		}
	}
	return ""
}

emit_platform :: proc(module: Module, target: Target, opts: Options) -> string {
	switch target {
	case .Android:
		if opts.kotlin != "" {
			if e := emit_kotlin(module, opts.kotlin); e != "" do return e
		}
		if opts.jni != "" {
			header := opts.header
			if header == "" do header = "binding.h"
			if e := emit_jni(module, opts.jni, header); e != "" do return e
		}
	case .Ios:
		if opts.swift != "" {
			if e := emit_swift(module, opts.swift); e != "" do return e
		}
	}
	if !opts.quiet {
		if opts.header != "" do fmt.println("odinbinder: wrote", opts.header)
		if target == .Android && opts.kotlin != "" do fmt.println("odinbinder: wrote", opts.kotlin)
		if target == .Android && opts.jni != "" do fmt.println("odinbinder: wrote", opts.jni)
		if target == .Ios && opts.swift != "" do fmt.println("odinbinder: wrote", opts.swift)
	}
	return ""
}
