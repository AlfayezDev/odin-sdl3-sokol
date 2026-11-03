package odinbinder

import "core:fmt"
import "core:strings"

Target :: enum {
	Android,
	Ios,
}

Direction :: enum {
	Export,
	Import,
}

Primitive :: enum {
	I8,
	I16,
	I32,
	I64,
	U8,
	U16,
	U32,
	U64,
	F32,
	F64,
	Bool,
	CString,
}

Param :: struct {
	name: string,
	typ:  string,
}

Function :: struct {
	name:      string,
	direction: Direction,
	thread:    string,
	params:    []Param,
	ret:       string,
}

Enum_Field :: struct {
	name:  string,
	value: i64,
}

Enum :: struct {
	name:       string,
	underlying: string,
	fields:     []Enum_Field,
}

Module :: struct {
	name:          string,
	android_pkg:   string,
	android_class: string,
	ios_module:    string,
	functions:     []Function,
	enums:         []Enum,
}

append_enum :: proc(arr: []Enum, e: Enum) -> []Enum {
	out := make([]Enum, len(arr) + 1)
	copy(out[:len(arr)], arr)
	out[len(arr)] = e
	return out
}

append_func :: proc(arr: []Function, f: Function) -> []Function {
	out := make([]Function, len(arr) + 1)
	copy(out[:len(arr)], arr)
	out[len(arr)] = f
	return out
}

is_nullable_cstring :: proc(name: string) -> bool {
	return name == "Nullable_CString"
}

find_enum :: proc(module: Module, name: string) -> (Enum, bool) {
	for e in module.enums {
		if e.name == name do return e, true
	}
	return {}, false
}

enum_underlying :: proc(module: Module, name: string) -> (string, bool) {
	if e, ok := find_enum(module, name); ok do return e.underlying, true
	return "", false
}

enum_first_field :: proc(e: Enum) -> string {
	if len(e.fields) == 0 do return "0"
	return e.fields[0].name
}

c_type_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "const char *"
	if u, ok := enum_underlying(module, name); ok do return c_type(u)
	return c_type(name)
}

kotlin_type_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "String?"
	if _, ok := find_enum(module, name); ok do return name
	return kotlin_type(name)
}

swift_type_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "String?"
	if _, ok := find_enum(module, name); ok do return name
	return swift_type(name)
}

jni_type_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "jstring"
	if u, ok := enum_underlying(module, name); ok do return jni_type(u)
	return jni_type(name)
}

jni_sig_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "Ljava/lang/String;"
	if u, ok := enum_underlying(module, name); ok do return jni_sig(u)
	return jni_sig(name)
}

jni_call_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "CallStaticObjectMethod"
	if u, ok := enum_underlying(module, name); ok do return jni_call(u)
	return jni_call(name)
}

swift_c_type_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "UnsafePointer<CChar>?"
	if u, ok := enum_underlying(module, name); ok do return swift_c_type(u)
	return swift_c_type(name)
}

kotlin_default_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "null"
	if e, ok := find_enum(module, name); ok do return fmt.tprintf("%s.%s", e.name, enum_first_field(e))
	return kotlin_default(name)
}

swift_default_for :: proc(module: Module, name: string) -> string {
	if is_nullable_cstring(name) do return "nil"
	if e, ok := find_enum(module, name); ok do return fmt.tprintf(".%s", swift_case(enum_first_field(e)))
	return swift_default(name)
}

parse_primitive :: proc(name: string) -> (Primitive, bool) {
	switch name {
	case "i8":
		return .I8, true
	case "i16":
		return .I16, true
	case "i32":
		return .I32, true
	case "i64":
		return .I64, true
	case "u8":
		return .U8, true
	case "u16":
		return .U16, true
	case "u32":
		return .U32, true
	case "u64":
		return .U64, true
	case "f32":
		return .F32, true
	case "f64":
		return .F64, true
	case "bool":
		return .Bool, true
	case "cstring":
		return .CString, true
	}
	return .I32, false
}

c_type :: proc(name: string) -> string {
	p, ok := parse_primitive(name)
	if !ok do return "void"
	switch p {
	case .I8:
		return "int8_t"
	case .I16:
		return "int16_t"
	case .I32:
		return "int32_t"
	case .I64:
		return "int64_t"
	case .U8:
		return "uint8_t"
	case .U16:
		return "uint16_t"
	case .U32:
		return "uint32_t"
	case .U64:
		return "uint64_t"
	case .F32:
		return "float"
	case .F64:
		return "double"
	case .Bool:
		return "bool"
	case .CString:
		return "const char *"
	}
	return "void"
}

kotlin_type :: proc(name: string) -> string {
	p, ok := parse_primitive(name)
	if !ok do return name
	switch p {
	case .I8:
		return "Byte"
	case .I16:
		return "Short"
	case .I32:
		return "Int"
	case .I64:
		return "Long"
	case .U8:
		return "Byte"
	case .U16:
		return "Short"
	case .U32:
		return "Int"
	case .U64:
		return "Long"
	case .F32:
		return "Float"
	case .F64:
		return "Double"
	case .Bool:
		return "Boolean"
	case .CString:
		return "String"
	}
	return name
}

swift_type :: proc(name: string) -> string {
	p, ok := parse_primitive(name)
	if !ok do return name
	switch p {
	case .I8:
		return "Int8"
	case .I16:
		return "Int16"
	case .I32:
		return "Int32"
	case .I64:
		return "Int64"
	case .U8:
		return "UInt8"
	case .U16:
		return "UInt16"
	case .U32:
		return "UInt32"
	case .U64:
		return "UInt64"
	case .F32:
		return "Float"
	case .F64:
		return "Double"
	case .Bool:
		return "Bool"
	case .CString:
		return "String"
	}
	return name
}

jni_type :: proc(name: string) -> string {
	if name == "" do return "void"
	p, ok := parse_primitive(name)
	if !ok do return "jobject"
	switch p {
	case .I8:
		return "jbyte"
	case .I16:
		return "jshort"
	case .I32:
		return "jint"
	case .I64:
		return "jlong"
	case .U8:
		return "jbyte"
	case .U16:
		return "jshort"
	case .U32:
		return "jint"
	case .U64:
		return "jlong"
	case .F32:
		return "jfloat"
	case .F64:
		return "jdouble"
	case .Bool:
		return "jboolean"
	case .CString:
		return "jstring"
	}
	return "jobject"
}

jni_sig :: proc(name: string) -> string {
	if name == "" do return "V"
	p, ok := parse_primitive(name)
	if !ok do return "Ljava/lang/Object;"
	switch p {
	case .I8, .U8:
		return "B"
	case .I16, .U16:
		return "S"
	case .I32, .U32:
		return "I"
	case .I64, .U64:
		return "J"
	case .F32:
		return "F"
	case .F64:
		return "D"
	case .Bool:
		return "Z"
	case .CString:
		return "Ljava/lang/String;"
	}
	return "V"
}

jni_call :: proc(name: string) -> string {
	if name == "" do return "CallStaticVoidMethod"
	p, ok := parse_primitive(name)
	if !ok do return "CallStaticObjectMethod"
	switch p {
	case .I8:
		return "CallStaticByteMethod"
	case .I16:
		return "CallStaticShortMethod"
	case .I32:
		return "CallStaticIntMethod"
	case .I64:
		return "CallStaticLongMethod"
	case .U8:
		return "CallStaticByteMethod"
	case .U16:
		return "CallStaticShortMethod"
	case .U32:
		return "CallStaticIntMethod"
	case .U64:
		return "CallStaticLongMethod"
	case .F32:
		return "CallStaticFloatMethod"
	case .F64:
		return "CallStaticDoubleMethod"
	case .Bool:
		return "CallStaticBooleanMethod"
	case .CString:
		return "CallStaticObjectMethod"
	}
	return "CallStaticVoidMethod"
}

kotlin_enum_literal :: proc(underlying: string, value: i64) -> string {
	switch underlying {
	case "i64":
		return fmt.tprintf("%dL", value)
	case "u32":
		v := value
		if v > 0x7fffffff do v -= 0x100000000
		return fmt.tprintf("%d", v)
	case "u8", "u16", "u64":
		return fmt.tprintf("%d", value)
	case:
		return fmt.tprintf("%d", value)
	}
}

function_uses_enum :: proc(module: Module, f: Function) -> bool {
	for p in f.params {
		if _, ok := find_enum(module, p.typ); ok do return true
	}
	if _, ok := find_enum(module, f.ret); ok do return true
	return false
}

kotlin_export_name :: proc(module: Module, f: Function) -> string {
	if function_uses_enum(module, f) do return fmt.tprintf("native%s", pascal(f.name))
	return camel(f.name)
}

jni_return_default_for :: proc(module: Module, name: string) -> string {
	if u, ok := enum_underlying(module, name); ok do return jni_return_default(u)
	return jni_return_default(name)
}

swift_raw_fallback :: proc(module: Module, name: string) -> string {
	if u, ok := enum_underlying(module, name); ok do return swift_default(u)
	return swift_default(name)
}

lower_first :: proc(s: string) -> string {
	if len(s) == 0 do return s
	b := strings.Builder{}
	strings.builder_init(&b)
	c := s[0]
	if c >= 'A' && c <= 'Z' do c += 'a' - 'A'
	strings.write_byte(&b, c)
	strings.write_string(&b, s[1:])
	return strings.to_string(b)
}

swift_case :: proc(s: string) -> string {
	return lower_first(camel(s))
}

camel :: proc(s: string) -> string {
	parts := strings.split(s, "_")
	if len(parts) == 0 do return s
	out := strings.Builder{}
	strings.builder_init(&out)
	strings.write_string(&out, parts[0])
	for p, i in parts {
		if i == 0 || len(p) == 0 do continue
		up := p[0]
		if up >= 'a' && up <= 'z' do up -= 'a' - 'A'
		strings.write_byte(&out, up)
		strings.write_string(&out, p[1:])
	}
	return strings.to_string(out)
}

pascal :: proc(s: string) -> string {
	parts := strings.split(s, "_")
	out := strings.Builder{}
	strings.builder_init(&out)
	for p in parts {
		if len(p) == 0 do continue
		up := p[0]
		if up >= 'a' && up <= 'z' do up -= 'a' - 'A'
		strings.write_byte(&out, up)
		strings.write_string(&out, p[1:])
	}
	res := strings.to_string(out)
	if res == "" do return "Bridge"
	return res
}
