package androidgen

import "core:fmt"
import "core:strconv"
import "core:strings"

Yaml_Line :: struct {
	text:   string,
	indent: int,
	number: int,
}

Yaml_Parser :: struct {
	lines: []Yaml_Line,
	idx:   int,
	err:   string,
}

yaml_parse :: proc(src: string) -> (Value, string) {
	p := Yaml_Parser{}
	text := src
	if strings.has_prefix(text, "\xEF\xBB\xBF") {
		text = text[3:]
	}
	raw := strings.split(text, "\n")
	lines := make([dynamic]Yaml_Line, 0, len(raw))
	for line, i in raw {
		l := line
		if strings.has_suffix(l, "\r") {
			l = l[:len(l) - 1]
		}
		indent := 0
		for indent < len(l) && l[indent] == ' ' do indent += 1
		if indent < len(l) && l[indent] == '\t' {
			return nil, fmt.tprintf("line %d: tabs cannot be used for indentation", i + 1)
		}
		append(&lines, Yaml_Line{text = l, indent = indent, number = i + 1})
	}
	p.lines = lines[:]

	// Skip a leading document marker.
	line, has := yaml_next_content(&p)
	if has && strings.trim_space(line.text) == "---" {
		p.idx += 1
	}
	if !has {
		return nil, ""
	}
	line, has = yaml_next_content(&p)
	if !has {
		return nil, ""
	}
	v := yaml_parse_block(&p, line.indent)
	if p.err != "" do return nil, p.err
	line, has = yaml_next_content(&p)
	if has {
		return nil, fmt.tprintf("line %d: unexpected content: %s", line.number, strings.trim_space(line.text))
	}
	return v, ""
}

yaml_error :: proc(p: ^Yaml_Parser, format: string, args: ..any) -> Value {
	line := p.idx + 1
	if p.idx < len(p.lines) do line = p.lines[p.idx].number
	p.err = strings.concatenate([]string{fmt.tprintf("line %d: ", line), fmt.tprintf(format, ..args)})
	return nil
}

yaml_ignorable :: proc(text: string) -> bool {
	s := strings.trim_space(text)
	return len(s) == 0 || s[0] == '#'
}

yaml_next_content :: proc(p: ^Yaml_Parser) -> (Yaml_Line, bool) {
	for p.idx < len(p.lines) {
		line := p.lines[p.idx]
		if yaml_ignorable(line.text) {
			p.idx += 1
			continue
		}
		return line, true
	}
	return Yaml_Line{}, false
}

yaml_starts_dash :: proc(text: string) -> bool {
	s := strings.trim_left_space(text)
	return len(s) > 0 && s[0] == '-' && (len(s) == 1 || s[1] == ' ' || s[1] == '\t')
}

yaml_parse_block :: proc(p: ^Yaml_Parser, indent: int) -> Value {
	line, has := yaml_next_content(p)
	if !has do return nil
	if line.indent < indent do return nil
	if yaml_starts_dash(line.text) {
		return yaml_parse_sequence(p, line.indent)
	}
	if yaml_find_mapping_colon(line.text) >= 0 {
		return yaml_parse_mapping(p, line.indent)
	}
	p.idx += 1
	return yaml_parse_scalar_text(strings.trim_space(line.text))
}

yaml_parse_mapping :: proc(p: ^Yaml_Parser, indent: int) -> Value {
	m := m_empty()
	for {
		line, has := yaml_next_content(p)
		if !has do break
		if line.indent < indent do break
		if line.indent > indent {
			yaml_error(p, "unexpected indentation")
			break
		}
		if yaml_starts_dash(line.text) do break
		p.idx += 1
		yaml_parse_entry_text(p, &m, line.text, indent)
		if p.err != "" do break
	}
	if p.err != "" do return nil
	return m
}

yaml_parse_entry_text :: proc(p: ^Yaml_Parser, m: ^Map, text: string, indent: int) {
	colon := yaml_find_mapping_colon(text)
	if colon < 0 {
		yaml_error(p, "expected 'key: value'")
		return
	}
	key := yaml_trim_key(text[:colon])
	if key == "" {
		yaml_error(p, "empty mapping key")
		return
	}
	if m_has(m^, key) {
		yaml_error(p, "duplicate key: %s", key)
		return
	}
	rest := strings.trim_space(text[colon + 1:])
	value: Value
	if rest == "" {
		line, has := yaml_next_content(p)
		if has && line.indent > indent {
			value = yaml_parse_block(p, line.indent)
		} else {
			value = nil
		}
	} else if rest[0] == '|' || rest[0] == '>' {
		value = yaml_parse_block_scalar(p, rest, indent)
	} else if rest[0] == '[' || rest[0] == '{' {
		full := yaml_collect_flow(p, rest)
		value = yaml_parse_flow_text(full)
	} else {
		value = yaml_parse_scalar_text(rest)
	}
	if p.err != "" do return
	m_set(m, key, value)
}

yaml_parse_sequence :: proc(p: ^Yaml_Parser, indent: int) -> Value {
	items := make([dynamic]Value)
	for {
		line, has := yaml_next_content(p)
		if !has do break
		if line.indent != indent do break
		if !yaml_starts_dash(line.text) do break
		p.idx += 1
		content := line.text[line.indent:]
		rest := strings.trim_left_space(content[1:])
		if rest == "" {
			next, has_next := yaml_next_content(p)
			if has_next && next.indent > indent {
				append(&items, yaml_parse_block(p, next.indent))
			} else {
				append(&items, nil)
			}
		} else if rest[0] == '|' || rest[0] == '>' {
			append(&items, yaml_parse_block_scalar(p, rest, indent))
		} else if rest[0] == '[' || rest[0] == '{' {
			append(&items, yaml_parse_flow_text(yaml_collect_flow(p, rest)))
		} else if yaml_find_mapping_colon(rest) >= 0 {
			m := m_empty()
			map_indent := indent + 2
			yaml_parse_entry_text(p, &m, rest, map_indent)
			for p.err == "" {
				next, has_next := yaml_next_content(p)
				if !has_next do break
				if next.indent != map_indent do break
				if yaml_starts_dash(next.text) do break
				p.idx += 1
				yaml_parse_entry_text(p, &m, next.text, map_indent)
			}
			append(&items, m)
		} else {
			append(&items, yaml_parse_scalar_text(strings.trim_space(rest)))
		}
		if p.err != "" do break
	}
	if p.err != "" do return nil
	return items[:]
}

// Returns the index of the mapping colon, or -1. A colon only separates a
// key when it is at top level and followed by whitespace or end-of-line.
yaml_find_mapping_colon :: proc(text: string) -> int {
	single := false
	double := false
	depth_bracket := 0
	depth_brace := 0
	for i := 0; i < len(text); i += 1 {
		c := text[i]
		if single {
			if c == '\'' {
				if i + 1 < len(text) && text[i + 1] == '\'' {
					i += 1
				} else {
					single = false
				}
			}
			continue
		}
		if double {
			if c == '\\' && i + 1 < len(text) {
				i += 1
			} else if c == '"' {
				double = false
			}
			continue
		}
		switch c {
		case '\'':
			single = true
		case '"':
			double = true
		case '[':
			depth_bracket += 1
		case ']':
			if depth_bracket > 0 do depth_bracket -= 1
		case '{':
			depth_brace += 1
		case '}':
			if depth_brace > 0 do depth_brace -= 1
		case ':':
			if depth_bracket == 0 && depth_brace == 0 {
				if i + 1 == len(text) || text[i + 1] == ' ' || text[i + 1] == '\t' {
					return i
				}
			}
		}
	}
	return -1
}

yaml_trim_key :: proc(s: string) -> string {
	k := strings.trim_space(s)
	if len(k) >= 2 && ((k[0] == '"' && k[len(k) - 1] == '"') || (k[0] == '\'' && k[len(k) - 1] == '\'')) {
		return yaml_unquote(k)
	}
	return strings.clone(k)
}

yaml_unquote :: proc(s: string) -> string {
	if len(s) < 2 do return strings.clone(s)
	if s[0] == '\'' && s[len(s) - 1] == '\'' {
		inner := s[1:len(s) - 1]
		out := strings.Builder{}
		strings.builder_init(&out)
		i := 0
		for i < len(inner) {
			if inner[i] == '\'' && i + 1 < len(inner) && inner[i + 1] == '\'' {
				strings.write_byte(&out, '\'')
				i += 2
			} else {
				strings.write_byte(&out, inner[i])
				i += 1
			}
		}
		return strings.to_string(out)
	}
	if s[0] == '"' && s[len(s) - 1] == '"' {
		inner := s[1:len(s) - 1]
		out := strings.Builder{}
		strings.builder_init(&out)
		i := 0
		for i < len(inner) {
			c := inner[i]
			if c == '\\' && i + 1 < len(inner) {
				i += 1
				switch inner[i] {
				case 'n':
					strings.write_byte(&out, '\n')
				case 'r':
					strings.write_byte(&out, '\r')
				case 't':
					strings.write_byte(&out, '\t')
				case 'b':
					strings.write_byte(&out, '\b')
				case 'f':
					strings.write_byte(&out, '\f')
				case '"':
					strings.write_byte(&out, '"')
				case '\\':
					strings.write_byte(&out, '\\')
				case '/':
					strings.write_byte(&out, '/')
				case:
					strings.write_byte(&out, inner[i])
				}
			} else {
				strings.write_byte(&out, c)
			}
			i += 1
		}
		return strings.to_string(out)
	}
	return strings.clone(s)
}

yaml_strip_comment :: proc(s: string) -> string {
	single := false
	double := false
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if single {
			if c == '\'' {
				if i + 1 < len(s) && s[i + 1] == '\'' {
					i += 1
				} else {
					single = false
				}
			}
			continue
		}
		if double {
			if c == '\\' && i + 1 < len(s) {
				i += 1
			} else if c == '"' {
				double = false
			}
			continue
		}
		switch c {
		case '\'':
			single = true
		case '"':
			double = true
		case '#':
			if i == 0 || s[i - 1] == ' ' || s[i - 1] == '\t' {
				return strings.trim_right_space(s[:i])
			}
		}
	}
	return strings.trim_space(s)
}

yaml_parse_scalar_text :: proc(text: string) -> Value {
	s := strings.trim_space(text)
	if len(s) == 0 do return nil
	if s[0] == '"' || s[0] == '\'' {
		if len(s) >= 2 && s[len(s) - 1] == s[0] {
			return yaml_unquote(s)
		}
	}
	if s[0] == '[' || s[0] == '{' {
		return yaml_parse_flow_text(s)
	}
	s = yaml_strip_comment(s)
	if len(s) == 0 do return nil
	switch s {
	case "null", "Null", "NULL", "~":
		return nil
	case "true", "True", "TRUE":
		return true
	case "false", "False", "FALSE":
		return false
	}
	if n, ok := strconv.parse_i64(s); ok {
		return n
	}
	if f, ok := strconv.parse_f64(s); ok {
		return f
	}
	return strings.clone(s)
}

yaml_collect_flow :: proc(p: ^Yaml_Parser, first: string) -> string {
	out := strings.Builder{}
	strings.builder_init(&out)
	strings.write_string(&out, first)
	depth := yaml_flow_depth(first)
	for depth > 0 && p.idx < len(p.lines) {
		line := p.lines[p.idx]
		p.idx += 1
		strings.write_byte(&out, ' ')
		text := strings.trim_space(line.text)
		strings.write_string(&out, text)
		depth += yaml_flow_depth(text)
	}
	if depth != 0 {
		yaml_error(p, "unterminated flow value")
	}
	return strings.to_string(out)
}

yaml_flow_depth :: proc(s: string) -> int {
	single := false
	double := false
	depth := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if single {
			if c == '\'' {
				if i + 1 < len(s) && s[i + 1] == '\'' {
					i += 1
				} else {
					single = false
				}
			}
			continue
		}
		if double {
			if c == '\\' && i + 1 < len(s) {
				i += 1
			} else if c == '"' {
				double = false
			}
			continue
		}
		switch c {
		case '\'':
			single = true
		case '"':
			double = true
		case '[', '{':
			depth += 1
		case ']', '}':
			depth -= 1
		}
	}
	return depth
}

Flow_Parser :: struct {
	s: string,
	i: int,
}

yaml_parse_flow_text :: proc(s: string) -> Value {
	fp := Flow_Parser{s = s}
	v := flow_value(&fp)
	return v
}

flow_skip :: proc(fp: ^Flow_Parser) {
	for fp.i < len(fp.s) {
		c := fp.s[fp.i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			fp.i += 1
		} else {
			break
		}
	}
}

flow_value :: proc(fp: ^Flow_Parser) -> Value {
	flow_skip(fp)
	if fp.i >= len(fp.s) do return nil
	c := fp.s[fp.i]
	if c == '[' do return flow_array(fp)
	if c == '{' do return flow_map(fp)
	if c == '"' || c == '\'' {
		start := fp.i
		quote := c
		fp.i += 1
		for fp.i < len(fp.s) {
			if quote == '\'' && fp.s[fp.i] == '\'' {
				if fp.i + 1 < len(fp.s) && fp.s[fp.i + 1] == '\'' {
					fp.i += 2
					continue
				}
				fp.i += 1
				break
			}
			if quote == '"' {
				if fp.s[fp.i] == '\\' && fp.i + 1 < len(fp.s) {
					fp.i += 2
					continue
				}
				if fp.s[fp.i] == '"' {
					fp.i += 1
					break
				}
			}
			fp.i += 1
		}
		return yaml_unquote(fp.s[start:fp.i])
	}
	start := fp.i
	for fp.i < len(fp.s) {
		c = fp.s[fp.i]
		if c == ',' || c == ']' || c == '}' do break
		if c == '#' && (fp.i == start || fp.s[fp.i - 1] == ' ' || fp.s[fp.i - 1] == '\t') do break
		fp.i += 1
	}
	return yaml_parse_scalar_text(strings.trim_space(fp.s[start:fp.i]))
}

flow_array :: proc(fp: ^Flow_Parser) -> Value {
	out := make([dynamic]Value)
	fp.i += 1
	for {
		flow_skip(fp)
		if fp.i >= len(fp.s) do break
		if fp.s[fp.i] == ']' {
			fp.i += 1
			break
		}
		append(&out, flow_value(fp))
		flow_skip(fp)
		if fp.i < len(fp.s) && fp.s[fp.i] == ',' {
			fp.i += 1
			continue
		}
		if fp.i < len(fp.s) && fp.s[fp.i] == ']' {
			fp.i += 1
			break
		}
		break
	}
	return out[:]
}

flow_map :: proc(fp: ^Flow_Parser) -> Value {
	out := m_empty()
	fp.i += 1
	for {
		flow_skip(fp)
		if fp.i >= len(fp.s) do break
		if fp.s[fp.i] == '}' {
			fp.i += 1
			break
		}
		key: string
		if fp.s[fp.i] == '"' || fp.s[fp.i] == '\'' {
			kv := flow_value(fp)
			key = value_string(kv)
		} else {
			start := fp.i
			for fp.i < len(fp.s) && fp.s[fp.i] != ':' && fp.s[fp.i] != ',' && fp.s[fp.i] != '}' {
				fp.i += 1
			}
			key = strings.trim_space(fp.s[start:fp.i])
		}
		flow_skip(fp)
		if fp.i < len(fp.s) && fp.s[fp.i] == ':' do fp.i += 1
		v := flow_value(fp)
		if key != "" do m_set(&out, strings.clone(key), v)
		flow_skip(fp)
		if fp.i < len(fp.s) && fp.s[fp.i] == ',' {
			fp.i += 1
			continue
		}
		if fp.i < len(fp.s) && fp.s[fp.i] == '}' {
			fp.i += 1
			break
		}
		break
	}
	return out
}

yaml_parse_block_scalar :: proc(p: ^Yaml_Parser, header: string, parent_indent: int) -> Value {
	style := header[0]
	chomp := byte(0)
	explicit_indent := 0
	for i := 1; i < len(header); i += 1 {
		c := header[i]
		if c == '-' || c == '+' {
			chomp = c
		} else if c >= '1' && c <= '9' {
			explicit_indent = int(c - '0')
		} else if c == ' ' || c == '#' {
			break
		}
	}

	start := p.idx
	content_indent := -1
	for p.idx < len(p.lines) {
		line := p.lines[p.idx]
		trimmed := strings.trim_space(line.text)
		if len(trimmed) == 0 {
			p.idx += 1
			continue
		}
		if line.indent <= parent_indent do break
		if content_indent < 0 || line.indent < content_indent {
			content_indent = line.indent
		}
		p.idx += 1
	}
	end := p.idx
	if explicit_indent > 0 {
		content_indent = parent_indent + explicit_indent
	}
	if content_indent < 0 do content_indent = parent_indent + 2

	out := strings.Builder{}
	strings.builder_init(&out)
	first_line := true
	if style == '|' {
		for i in start ..< end {
			line := p.lines[i]
			if len(strings.trim_space(line.text)) == 0 {
				strings.write_byte(&out, '\n')
				first_line = false
				continue
			}
			if !first_line do strings.write_byte(&out, '\n')
			text := line.text
			if len(text) >= content_indent do text = text[content_indent:]
			else do text = strings.trim_left_space(text)
			strings.write_string(&out, text)
			first_line = false
		}
	} else {
		prev_blank := true
		for i in start ..< end {
			line := p.lines[i]
			if len(strings.trim_space(line.text)) == 0 {
				strings.write_byte(&out, '\n')
				prev_blank = true
				first_line = false
				continue
			}
			text := line.text
			if len(text) >= content_indent do text = text[content_indent:]
			else do text = strings.trim_left_space(text)
			if !first_line && !prev_blank do strings.write_byte(&out, ' ')
			strings.write_string(&out, text)
			prev_blank = false
			first_line = false
		}
	}

	result := strings.to_string(out)
	switch chomp {
	case '-':
		result = strings.trim_right(result, "\n")
	case '+':
		// keep as-is
	case:
		result = strings.trim_right(result, "\n")
		result = strings.concatenate([]string{result, "\n"})
	}
	return result
}
