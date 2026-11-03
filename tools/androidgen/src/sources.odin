package androidgen

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Source_Result :: struct {
	manifest_found: bool,
	manifest_path:  string,
	proguard:       [dynamic]string,
	tracked:        [dynamic]string,
	links:          map[string]string,
}

build_sources :: proc(project: ^Project, target: ^Target, module_dir: string) -> (Source_Result, string) {
	result := Source_Result{links = make(map[string]string)}
	src_main := join_path(module_dir, "src/main")
	os.mkdir_all(src_main)

	for source in target.sources {
		if source.path == "" do continue
		path := source.path
		if !filepath.is_abs(path) do path = join_path(project.base_dir, path)
		path = clean_path(path)
		if !os.exists(path) {
			if source.optional {
				append(&project.warnings, fmt.tprintf("target %s: optional source missing: %s", target.name, path))
				continue
			}
			return result, fmt.tprintf("target %s: source does not exist: %s", target.name, path)
		}
		append(&result.tracked, path)
		info, stat_err := os.stat(path, context.allocator)
		if stat_err != nil do return result, fmt.tprintf("target %s: cannot stat source: %s", target.name, path)
		is_dir := info.type == .Directory
		os.file_info_delete(info, context.allocator)
		if is_dir {
			err := add_source_dir(project, target, &result, path, source, src_main, module_dir)
			if err != "" do return result, err
		} else {
			err := add_source_file(project, target, &result, path, source, source.build_phase, filepath.base(path), src_main, module_dir)
			if err != "" do return result, err
		}
	}
	return result, ""
}

add_source_dir :: proc(project: ^Project, target: ^Target, result: ^Source_Result, path: string, source: Source, src_main, module_dir: string) -> string {
	base := filepath.base(path)
	phase := source.build_phase
	if phase == "resources" do phase = "res"
	if phase == "headers" || phase == "native" do return ""
	if phase == "sources" {
		return walk_and_link_mixed(project, target, result, path, source, src_main, module_dir)
	}
	if phase != "" {
		return walk_and_link(project, target, result, path, source, phase, "", src_main, module_dir)
	}
	switch base {
	case "java":
		return walk_and_link(project, target, result, path, source, "java", "", src_main, module_dir)
	case "kotlin":
		return walk_and_link(project, target, result, path, source, "kotlin", "", src_main, module_dir)
	case "res":
		return walk_and_link(project, target, result, path, source, "res", "", src_main, module_dir)
	case "assets":
		return walk_and_link(project, target, result, path, source, "assets", "", src_main, module_dir)
	case "jniLibs", "jni":
		return walk_and_link(project, target, result, path, source, "jniLibs", "", src_main, module_dir)
	case "aidl":
		return walk_and_link(project, target, result, path, source, "aidl", "", src_main, module_dir)
	}
	// Mixed directory: classify each file by path segment or extension.
	return walk_and_link_mixed(project, target, result, path, source, src_main, module_dir)
}

walk_and_link :: proc(project: ^Project, target: ^Target, result: ^Source_Result, root: string, source: Source, phase, rel_prefix, src_main, module_dir: string) -> string {
	files := make([dynamic]string)
	walk_err := walk_files(root, &files)
	if walk_err != "" do return walk_err
	sort_strings(files[:])
	for file in files {
		rel, rel_err := filepath.rel(root, file)
		if rel_err != nil do continue
		rel = clean_rel(rel)
		if !source_included(rel, source) do continue
		dest := rel
		if rel_prefix != "" do dest = join_path(rel_prefix, rel)
		err := add_source_file(project, target, result, file, source, phase, dest, src_main, module_dir)
		if err != "" do return err
	}
	return ""
}

walk_and_link_mixed :: proc(project: ^Project, target: ^Target, result: ^Source_Result, root: string, source: Source, src_main, module_dir: string) -> string {
	files := make([dynamic]string)
	walk_err := walk_files(root, &files)
	if walk_err != "" do return walk_err
	sort_strings(files[:])
	for file in files {
		rel, rel_err := filepath.rel(root, file)
		if rel_err != nil do continue
		rel = clean_rel(rel)
		if !source_included(rel, source) do continue
		phase, dest := classify_file(rel, filepath.base(file))
		if phase == "" || phase == "none" {
			if debug_enabled() do fmt.eprintln("androidgen: ignoring unclassified source", file)
			continue
		}
		err := add_source_file(project, target, result, file, source, phase, dest, src_main, module_dir)
		if err != "" do return err
	}
	return ""
}

classify_file :: proc(rel, base: string) -> (string, string) {
	segs := strings.split(rel, "/")
	phase := ""
	start := 0
	for s, i in segs {
		switch s {
		case "java", "kotlin", "res", "assets", "jniLibs", "aidl":
			phase = s
			start = i + 1
		}
		if phase != "" do break
	}
	if phase != "" {
		if start >= len(segs) do return "", ""
		return phase, strings.join(segs[start:], "/")
	}
	if base == "AndroidManifest.xml" do return "manifest", "AndroidManifest.xml"
	ext, _ := strings.to_lower(filepath.ext(base))
	switch ext {
	case ".java":
		return "java", rel
	case ".kt", ".kts":
		return "kotlin", rel
	case ".so":
		return "jniLibs", rel
	case ".aidl":
		return "aidl", rel
	case ".pro":
		return "proguard", rel
	case ".xml":
		return "", ""
	}
	return "", ""
}

add_source_file :: proc(project: ^Project, target: ^Target, result: ^Source_Result, file: string, source: Source, phase, dest_rel, src_main, module_dir: string) -> string {
	dest_name := dest_rel
	if dest_name == "" do dest_name = filepath.base(file)
	resolved_phase := phase
	if resolved_phase == "resources" do resolved_phase = "res"
	if resolved_phase == "headers" || resolved_phase == "native" do return ""
	if resolved_phase == "sources" {
		resolved_phase, dest_name = classify_file(dest_name, filepath.base(file))
	}
	if filepath.base(file) == "AndroidManifest.xml" && resolved_phase != "" && resolved_phase != "none" {
		resolved_phase = "manifest"
	}
	switch resolved_phase {
	case "", "none":
		return ""
	case "manifest":
		if result.manifest_found {
			return fmt.tprintf("target %s: multiple AndroidManifest.xml sources", target.name)
		}
		result.manifest_found = true
		result.manifest_path = file
		return link_at(file, join_path(src_main, "AndroidManifest.xml"))
	case "proguard":
		append(&result.proguard, file)
		if len(result.proguard) > 1 {
			return fmt.tprintf("target %s: multiple proguard source files are not supported", target.name)
		}
		return link_at(file, join_path(module_dir, "proguard-rules.pro"))
	case "copyFiles", "javaResources":
		return link_at(file, join_path(join_path(src_main, "assets"), dest_name))
	}
	dest := join_path(join_path(src_main, resolved_phase), dest_name)
	if previous, has := result.links[dest]; has {
		if previous == file do return ""
		return fmt.tprintf("target %s: source collision at %s (%s and %s)", target.name, dest, previous, file)
	}
	result.links[dest] = file
	return link_at(file, dest)
}

walk_files :: proc(root: string, out: ^[dynamic]string) -> string {
	infos, err := os.read_all_directory_by_path(root, context.allocator)
	if err != nil do return fmt.tprintf("cannot read directory: %s", root)
	defer os.file_info_slice_delete(infos, context.allocator)
	names := make([dynamic]string)
	for fi in infos do append(&names, fi.name)
	sort_strings(names[:])
	for name in names {
		full := join_path(root, name)
		if lfi, lerr := os.stat_do_not_follow_links(full, context.allocator); lerr == nil {
			is_link := lfi.type == .Symlink
			os.file_info_delete(lfi, context.allocator)
			if is_link {
				sfi, serr := os.stat(full, context.allocator)
				if serr != nil do continue
				stype := sfi.type
				os.file_info_delete(sfi, context.allocator)
				if stype == .Directory do continue
				if stype == .Regular do append(out, full)
				continue
			}
		}
		fi, stat_err := os.stat(full, context.allocator)
		if stat_err != nil do continue
		ftype := fi.type
		os.file_info_delete(fi, context.allocator)
		#partial switch ftype {
		case .Directory:
			sub_err := walk_files(full, out)
			if sub_err != "" do return sub_err
		case .Regular:
			append(out, full)
		case:
		}
	}
	return ""
}

link_at :: proc(target, link: string) -> string {
	parent := filepath.dir(link)
	if parent != "" do os.mkdir_all(parent)
	if fi, err := os.stat_do_not_follow_links(link, context.allocator); err == nil {
		ftype := fi.type
		os.file_info_delete(fi, context.allocator)
		if ftype == .Directory {
			_ = os.remove_all(link)
		} else {
			_ = os.remove(link)
		}
	}
	target_abs, abs_err := filepath.abs(target)
	if abs_err != nil do return fmt.tprintf("cannot resolve source path: %s", target)
	if err := os.symlink(target_abs, link); err != nil {
		return fmt.tprintf("cannot link %s -> %s: %v", link, target_abs, err)
	}
	return ""
}

source_included :: proc(rel: string, source: Source) -> bool {
	if len(source.includes) > 0 {
		included := false
		for pattern in source.includes {
			if glob_match(pattern, rel) do included = true
		}
		if !included do return false
	}
	for pattern in source.excludes {
		if glob_match(pattern, rel) do return false
	}
	return true
}

glob_match :: proc(pattern, path: string) -> bool {
	p := strings.split(pattern, "/")
	s := strings.split(path, "/")
	return glob_match_parts(p, s)
}

glob_match_parts :: proc(pattern, path: []string) -> bool {
	if len(pattern) == 0 do return len(path) == 0
	if pattern[0] == "**" {
		for i := 0; i <= len(path); i += 1 {
			if glob_match_parts(pattern[1:], path[i:]) do return true
		}
		return false
	}
	if len(path) == 0 do return false
	if !glob_match_segment(pattern[0], path[0]) do return false
	return glob_match_parts(pattern[1:], path[1:])
}

glob_match_segment :: proc(pattern, text: string) -> bool {
	pi := 0
	ti := 0
	star := -1
	match := 0
	for ti < len(text) {
		if pi < len(pattern) {
			switch pattern[pi] {
			case '?':
				pi += 1
				ti += 1
				continue
			case '*':
				star = pi
				match = ti
				pi += 1
				continue
			case '[':
				if pi + 1 < len(pattern) {
					end := pi + 1
					negate := false
					if end < len(pattern) && (pattern[end] == '!' || pattern[end] == '^') {
						negate = true
						end += 1
					}
					start := end
					for end < len(pattern) && pattern[end] != ']' do end += 1
					if end < len(pattern) {
						hit := false
						for k := start; k < end; k += 1 {
							if pattern[k] == text[ti] do hit = true
							if k + 2 < end && pattern[k + 1] == '-' && pattern[k] <= text[ti] && text[ti] <= pattern[k + 2] do hit = true
						}
						if hit != negate {
							pi = end + 1
							ti += 1
							continue
						}
					}
				}
			case:
				if pattern[pi] == text[ti] {
					pi += 1
					ti += 1
					continue
				}
			}
		}
		if star >= 0 {
			pi = star + 1
			match += 1
			ti = match
			continue
		}
		return false
	}
	for pi < len(pattern) && pattern[pi] == '*' do pi += 1
	return pi == len(pattern)
}

clean_path :: proc(path: string) -> string {
	out, err := filepath.clean(path)
	if err == nil do return out
	return path
}

clean_rel :: proc(path: string) -> string {
	out, err := filepath.clean(path)
	if err == nil {
		if strings.has_prefix(out, "./") do return out[2:]
		return out
	}
	return path
}

debug_enabled :: proc() -> bool {
	v, found := os.lookup_env("ANDROIDGEN_DEBUG", context.allocator)
	return found && (v == "1" || v == "true")
}
