package odinbinder

import "core:path/filepath"
import "core:strings"

join_path :: proc(a, b: string) -> string {
	return join_paths(a, b)
}

join_paths :: proc(parts: ..string) -> string {
	res, err := filepath.join(parts)
	if err == nil do return res
	return strings.join(parts, "/")
}
