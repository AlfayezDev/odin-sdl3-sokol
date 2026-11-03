package odinbinder

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strconv"
import "core:strings"

parse_binding_file :: proc(path: string) -> (Module, string) {
	src, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return {}, fmt.tprintf("cannot read %s", path)

	pkg := ast.new(ast.Package, tokenizer.Pos{}, tokenizer.Pos{})
	file := ast.new(ast.File, tokenizer.Pos{}, tokenizer.Pos{})
	file.pkg = pkg
	file.src = string(src)
	file.fullpath = path
	pkg.files[path] = file

	p := parser.Parser {
		flags = {.Optional_Semicolons},
	}
	if !parser.parse_file(&p, file) {
		return {}, fmt.tprintf("failed to parse %s", path)
	}

	module := Module{}
	found_config := false
	for d in file.decls {
		#partial switch v in d.derived_stmt {
		case ^ast.Value_Decl:
			attrs := binding_attrs(v.attributes)
			is_config := false
			for n in v.names {
				#partial switch id in n.derived_expr {
				case ^ast.Ident:
					if id.name == "_config" do is_config = true
				}
			}
			if is_config && !found_config {
				found_config = true
				if name, ok := attrs["name"]; ok && name != "" do module.name = name
				if pkg_name, ok := attrs["android_package"]; ok && pkg_name != "" do module.android_pkg = pkg_name
				if cls, ok := attrs["android_class"]; ok && cls != "" do module.android_class = cls
				if mod, ok := attrs["ios_module"]; ok && mod != "" do module.ios_module = mod
				continue
			}
			f, is_func, ferr := parse_function_decl(v, attrs)
			if ferr != "" do return {}, fmt.tprintf("%s: %s", path, ferr)
			if is_func do module.functions = append_func(module.functions, f)
		}
	}
	if len(module.functions) == 0 && !found_config {
		return {}, fmt.tprintf("%s: no proc c declarations found", path)
	}
	return module, ""
}

binding_attrs :: proc(attributes: [dynamic]^ast.Attribute) -> map[string]string {
	out := make(map[string]string)
	for attr in attributes {
		for elem in attr.elems {
			#partial switch fv in elem.derived_expr {
			case ^ast.Field_Value:
				name := expr_string(fv.field)
				if name != "odinbinder" do continue
				#partial switch cv in fv.value.derived_expr {
				case ^ast.Comp_Lit:
					for item in cv.elems {
						#partial switch inner in item.derived_expr {
						case ^ast.Field_Value:
							key := expr_string(inner.field)
							if key != "" do out[key] = expr_string(inner.value)
						}
					}
				case:
					if value := expr_string(fv.value); value != "" do out["$"] = value
				}
			}
		}
	}
	return out
}

expr_string :: proc(e: ^ast.Expr) -> string {
	if e == nil do return ""
	#partial switch v in e.derived_expr {
	case ^ast.Ident:
		return v.name
	case ^ast.Basic_Lit:
		text := v.tok.text
		if unquoted, _, ok := strconv.unquote_string(text); ok do return unquoted
		return text
	}
	return ""
}

parse_function_decl :: proc(
	v: ^ast.Value_Decl,
	attrs: map[string]string,
) -> (
	Function,
	bool,
	string,
) {
	if len(v.names) != 1 || len(v.values) != 1 do return {}, false, ""
	name := expr_string(v.names[0])
	if name == "" do return {}, false, ""
	proc_type: ^ast.Proc_Type
	is_export := false
	#partial switch val in v.values[0].derived_expr {
	case ^ast.Proc_Lit:
		proc_type = val.type
		is_export = val.body != nil
	case ^ast.Proc_Type:
		proc_type = val
	case:
		return {}, false, ""
	}
	if proc_type == nil do return {}, false, ""
	is_c := false
	if cc, ok := proc_type.calling_convention.(string); ok {
		is_c = strings.trim(cc, "\"") == "c"
	} else if cc, ok := proc_type.calling_convention.(ast.Proc_Calling_Convention_Extra); ok {
		is_c = cc == .Foreign_Block_Default
	}
	if !is_c do return {}, false, fmt.tprintf("%s must use proc c calling convention", name)

	if dir, ok := attrs["direction"]; ok {
		switch dir {
		case "export":
			is_export = true
		case "import":
			is_export = false
		case:
			return {}, false, fmt.tprintf("%s: invalid direction %q", name, dir)
		}
	}
	thread := ""
	if t, ok := attrs["thread"]; ok do thread = t

	params := make([dynamic]Param)
	if proc_type.params != nil {
		for field in proc_type.params.list {
			ptype := expr_string(field.type)
			if ptype == "" do return {}, false, fmt.tprintf("%s: unsupported parameter type", name)
			if _, ok := parse_primitive(ptype); !ok {
				return {}, false, fmt.tprintf("%s: unsupported type %q (records/enums/objects are not in this binder version)", name, ptype)
			}
			for pname_expr in field.names {
				pname := expr_string(pname_expr)
				if pname == "" do return {}, false, fmt.tprintf("%s: parameter has no name", name)
				append(&params, Param{name = pname, typ = ptype})
			}
		}
	}

	ret := ""
	if proc_type.results != nil && len(proc_type.results.list) > 0 {
		if len(proc_type.results.list) > 1 do return {}, false, fmt.tprintf("%s: multiple return values are not supported", name)
		ret = expr_string(proc_type.results.list[0].type)
		if ret == "" do return {}, false, fmt.tprintf("%s: unsupported return type", name)
		if _, ok := parse_primitive(ret); !ok {
			return {}, false, fmt.tprintf("%s: unsupported return type %q (records/enums/objects are not in this binder version)", name, ret)
		}
	}

	direction := Direction.Import
	if is_export do direction = .Export
	return Function {
			name = name,
			direction = direction,
			thread = thread,
			params = params[:],
			ret = ret,
		},
		true,
		""
}
