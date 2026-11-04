package odinbinder

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

write_text :: proc(path, content: string) -> string {
	parent := filepath.dir(path)
	if parent != "" do os.mkdir_all(parent)
	body := strings.trim_right(content, "\n")
	trimmed := strings.concatenate([]string{body, "\n"})
	if existing, err := os.read_entire_file_from_path(path, context.allocator); err == nil {
		if string(existing) == trimmed do return ""
	}
	if err := os.write_entire_file_from_string(path, trimmed); err != nil {
		return fmt.tprintf("cannot write %s", path)
	}
	return ""
}

line :: proc(b: ^strings.Builder, indent: int, text: string) {
	if text == "" {
		strings.write_byte(b, '\n')
		return
	}
	for _ in 0 ..< indent * 4 do strings.write_byte(b, ' ')
	strings.write_string(b, text)
	strings.write_byte(b, '\n')
}
