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
	for d in file.decls {
		#partial switch v in d.derived_stmt {
		case ^ast.Value_Decl:
			if err := collect_enum_decl(v, &module); err != "" {
				return {}, fmt.tprintf("%s: %s", path, err)
			}
		}
	}
	found_config := false
	for d in file.decls {
		#partial switch v in d.derived_stmt {
		case ^ast.Value_Decl:
			if err := parse_value_decl(v, &module, &found_config); err != "" {
				return {}, fmt.tprintf("%s: %s", path, err)
			}
		case ^ast.Foreign_Block_Decl:
			#partial switch body in v.body.derived_stmt {
			case ^ast.Block_Stmt:
				for stmt in body.stmts {
					#partial switch vd in stmt.derived_stmt {
					case ^ast.Value_Decl:
						if err := parse_value_decl(vd, &module, &found_config); err != "" {
							return {}, fmt.tprintf("%s: %s", path, err)
						}
					}
				}
			}
		}
	}
	if len(module.functions) == 0 && !found_config {
		return {}, fmt.tprintf("%s: no proc c declarations found", path)
	}
	return module, ""
}

collect_enum_decl :: proc(v: ^ast.Value_Decl, module: ^Module) -> string {
	if len(v.names) != 1 || len(v.values) != 1 do return ""
	name := expr_string(v.names[0])
	if name == "" do return ""
	#partial switch e in v.values[0].derived_expr {
	case ^ast.Enum_Type:
		if _, exists := find_enum(module^, name); exists {
			return fmt.tprintf("duplicate enum %s", name)
		}
		enum_decl, err := parse_enum_decl(name, e)
		if err != "" do return err
		module.enums = append_enum(module.enums, enum_decl)
	}
	return ""
}

parse_enum_decl :: proc(name: string, e: ^ast.Enum_Type) -> (Enum, string) {
	if e.base_type == nil {
		return {}, fmt.tprintf("enum %s: base type must be explicitly i32 or u32", name)
	}
	underlying := expr_string(e.base_type)
	if underlying != "i32" && underlying != "u32" {
		return {}, fmt.tprintf("enum %s: base type must be i32 or u32", name)
	}
	fields := make([dynamic]Enum_Field)
	next: i64 = 0
	for f in e.fields {
		#partial switch field in f.derived_expr {
		case ^ast.Ident:
			for existing in fields {
				if existing.name == field.name do return {}, fmt.tprintf("enum %s: duplicate field %s", name, field.name)
			}
			append(&fields, Enum_Field{name = field.name, value = next})
			next += 1
		case ^ast.Field_Value:
			fname := expr_string(field.field)
			if fname == "" do return {}, fmt.tprintf("enum %s: field has no name", name)
			for existing in fields {
				if existing.name == fname do return {}, fmt.tprintf("enum %s: duplicate field %s", name, fname)
			}
			value: i64
			parsed := false
			#partial switch lit in field.value.derived_expr {
			case ^ast.Basic_Lit:
				v, ok := strconv.parse_int(lit.tok.text)
				if ok {
					value = i64(v)
					parsed = true
				}
			case ^ast.Unary_Expr:
				if lit.op.kind == .Sub {
					#partial switch inner in lit.expr.derived_expr {
					case ^ast.Basic_Lit:
						v, ok := strconv.parse_int(inner.tok.text)
						if ok {
							value = -i64(v)
							parsed = true
						}
					}
				}
			}
			if !parsed {
				return {}, fmt.tprintf("enum %s.%s: value must be an integer literal", name, fname)
			}
			if underlying == "i32" && (value < -2147483648 || value > 2147483647) {
				return {}, fmt.tprintf("enum %s.%s: value does not fit i32", name, fname)
			}
			if underlying == "u32" && (value < 0 || value > 4294967295) {
				return {}, fmt.tprintf("enum %s.%s: value does not fit u32", name, fname)
			}
			append(&fields, Enum_Field{name = fname, value = value})
			next = value + 1
		case:
			return {}, fmt.tprintf("enum %s: unsupported field", name)
		}
	}
	if len(fields) == 0 do return {}, fmt.tprintf("enum %s has no fields", name)
	for i in 0 ..< len(fields) {
		for j in i + 1 ..< len(fields) {
			if swift_case(fields[i].name) == swift_case(fields[j].name) {
				return {}, fmt.tprintf("enum %s: fields %s and %s collide in Swift", name, fields[i].name, fields[j].name)
			}
		}
	}
	return Enum{name = name, underlying = underlying, fields = fields[:]}, ""
}

parse_value_decl :: proc(v: ^ast.Value_Decl, module: ^Module, found_config: ^bool) -> string {
	attrs := binding_attrs(v.attributes)
	is_config := false
	for n in v.names {
		#partial switch id in n.derived_expr {
		case ^ast.Ident:
			if id.name == "_config" do is_config = true
		}
	}
	if is_config && !found_config^ {
		found_config^ = true
		if name, ok := attrs["name"]; ok && name != "" do module.name = name
		if pkg_name, ok := attrs["android_package"]; ok && pkg_name != "" do module.android_pkg = pkg_name
		if cls, ok := attrs["android_class"]; ok && cls != "" do module.android_class = cls
		if mod, ok := attrs["ios_module"]; ok && mod != "" do module.ios_module = mod
		return ""
	}
	f, is_func, ferr := parse_function_decl(v, attrs, module^)
	if ferr != "" do return ferr
	if is_func do module.functions = append_func(module.functions, f)
	return ""
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

is_supported_type :: proc(module: Module, name: string, is_export: bool, is_return: bool) -> bool {
	if _, ok := parse_primitive(name); ok do return true
	if is_nullable_cstring(name) {
		return !is_export && !is_return
	}
	if _, ok := find_enum(module, name); ok do return true
	return false
}

parse_function_decl :: proc(
	v: ^ast.Value_Decl,
	attrs: map[string]string,
	module: Module,
) -> (
	Function,
	bool,
	string,
) {
	if len(v.names) != 1 || len(v.values) != 1 do return {}, false, ""
	name := expr_string(v.names[0])
	if name == "" do return {}, false, ""
	if is_keyword(c_keywords[:], name) {
		return {}, false, fmt.tprintf("%s: function name is a C keyword", name)
	}
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
	if !is_c {
		if len(attrs) > 0 do return {}, false, fmt.tprintf("%s must use proc c calling convention", name)
		return {}, false, ""
	}

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

	if !is_export && java_is_keyword(camel(name)) {
		return {}, false, fmt.tprintf("%s: import name is a Java keyword", name)
	}

	params := make([dynamic]Param)
	if proc_type.params != nil {
		for field in proc_type.params.list {
			ptype := expr_string(field.type)
			if ptype == "" do return {}, false, fmt.tprintf("%s: unsupported parameter type", name)
			if !is_supported_type(module, ptype, is_export, false) {
				if is_nullable_cstring(ptype) {
					return {}, false, fmt.tprintf("%s: Nullable_CString is only supported for import parameters", name)
				}
				return {}, false, fmt.tprintf("%s: unsupported type %q", name, ptype)
			}
			for pname_expr in field.names {
				pname := expr_string(pname_expr)
				if pname == "" do return {}, false, fmt.tprintf("%s: parameter has no name", name)
				append(&params, Param{name = safe_param_name(pname), typ = ptype})
			}
		}
	}

	ret := ""
	if proc_type.results != nil && len(proc_type.results.list) > 0 {
		if len(proc_type.results.list) > 1 do return {}, false, fmt.tprintf("%s: multiple return values are not supported", name)
		ret = expr_string(proc_type.results.list[0].type)
		if ret == "" do return {}, false, fmt.tprintf("%s: unsupported return type", name)
		if !is_supported_type(module, ret, is_export, true) {
			if is_nullable_cstring(ret) {
				return {}, false, fmt.tprintf("%s: Nullable_CString cannot be returned", name)
			}
			return {}, false, fmt.tprintf("%s: unsupported return type %q", name, ret)
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
