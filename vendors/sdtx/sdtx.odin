// Odin bindings for the vendored sokol_debugtext.h (impl compiled in
// app/native/sokol_shim.c via SOKOL_IMPL).
package sdtx


import sg "libs:sg"

foreign import sdtx_impl "sokol_debugtext_impl"

MAX_FONTS :: 8
MAX_COMMANDS :: 4096

Range :: struct {
	ptr:   rawptr,
	size:  uint,
}

Font_Desc :: struct {
	data:      Range,
	first_char: u8,
	last_char: u8,
}

Context_Desc :: struct {
	max_commands: i32,
	char_buf_size: i32,
	canvas_width:  f32,
	canvas_height: f32,
	tab_width:     i32,
	color_format:  sg.Pixel_Format,
	depth_format:  sg.Pixel_Format,
	sample_count:  i32,
}

Desc :: struct {
	context_pool_size: i32,
	printf_buf_size:   i32,
	fonts:             [MAX_FONTS]Font_Desc,
	context_desc:      Context_Desc,
	allocator:         rawptr,
	logger:            rawptr,
}

foreign sdtx_impl {
@(link_name="sdtx_setup")
		setup :: proc "c" (desc: ^Desc) ---
@(link_name="sdtx_shutdown")
		shutdown :: proc "c" () ---
	@(link_name="sdtx_font_kc853")
	font_kc853 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_kc854")
	font_kc854 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_z1013")
	font_z1013 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_cpc")
	font_cpc :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_c64")
	font_c64 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_oric")
	font_oric :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_kc85_1")
	font_kc85_1 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_kc85_2")
	font_kc85_2 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_z9001")
	font_z9001 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_hc908")
	font_hc908 :: proc "c" () -> Font_Desc ---
	@(link_name="sdtx_font_coco3")
	font_coco3 :: proc "c" () -> Font_Desc ---
@(link_name="sdtx_default_context")
		default_context :: proc "c" () ---
@(link_name="sdtx_canvas")
		canvas :: proc "c" (width, height: f32) ---
@(link_name="sdtx_pos")
		pos :: proc "c" (x, y: f32) ---
@(link_name="sdtx_origin")
		origin :: proc "c" (x, y: f32) ---
@(link_name="sdtx_home")
		home :: proc "c" () ---
@(link_name="sdtx_crlf")
		crlf :: proc "c" () ---
@(link_name="sdtx_tab")
		tab :: proc "c" () ---
@(link_name="sdtx_pan_forward")
		pan_forward :: proc "c" (p: f32) ---
@(link_name="sdtx_font")
		font :: proc "c" (font_index: u32) ---
@(link_name="sdtx_color1i")
		color1i :: proc "c" (rgba: u32) ---
@(link_name="sdtx_color3b")
		color3b :: proc "c" (r, g, b: u8) ---
@(link_name="sdtx_color3f")
		color3f :: proc "c" (r, g, b: f32) ---
@(link_name="sdtx_color4b")
		color4b :: proc "c" (r, g, b, a: u8) ---
@(link_name="sdtx_color4f")
		color4f :: proc "c" (r, g, b, a: f32) ---
@(link_name="sdtx_puts")
		puts :: proc "c" (str: cstring) ---
@(link_name="sdtx_putc")
		putc :: proc "c" (chr: u8) ---
@(link_name="sdtx_draw")
		draw :: proc "c" () ---
@(link_name="sdtx_draw_layer")
		draw_layer :: proc "c" (layer: i32) ---
@(link_name="sdtx_draw_ex")
		draw_ex :: proc "c" (layer, viewport_index: i32) ---
}
