package odinbinder

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

Module :: struct {
	name:          string,
	android_pkg:   string,
	android_class: string,
	ios_module:    string,
	functions:     []Function,
}

append_func :: proc(arr: []Function, f: Function) -> []Function {
	out := make([]Function, len(arr) + 1)
	copy(out[:len(arr)], arr)
	out[len(arr)] = f
	return out
}

primitive_name :: proc(p: Primitive) -> string {
	switch p {
	case .I8:
		return "i8"
	case .I16:
		return "i16"
	case .I32:
		return "i32"
	case .I64:
		return "i64"
	case .U8:
		return "u8"
	case .U16:
		return "u16"
	case .U32:
		return "u32"
	case .U64:
		return "u64"
	case .F32:
		return "f32"
	case .F64:
		return "f64"
	case .Bool:
		return "bool"
	case .CString:
		return "cstring"
	}
	return ""
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
		return "UByte"
	case .U16:
		return "UShort"
	case .U32:
		return "UInt"
	case .U64:
		return "ULong"
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
