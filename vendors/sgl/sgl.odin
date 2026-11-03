// Odin bindings for the vendored sokol_gl.h (impl compiled in
// app/native/sokol_shim.c via SOKOL_IMPL).
package sgl

import sg "libs:sg"

MAX_DEFAULT_ATTRIBUTES :: 16

Pipeline :: struct {id: u32}
Context :: struct {id: u32}

Desc :: struct {
	max_vertices:      i32,
	max_commands:      i32,
	context_pool_size: i32,
	pipeline_pool_size: i32,
	color_format:      sg.Pixel_Format,
	depth_format:      sg.Pixel_Format,
	sample_count:      i32,
	face_winding:      sg.Face_Winding,
	allocator:         rawptr, // sgl_allocator_t (unused)
	logger:            rawptr, // sgl_logger_t (unused)
}

foreign {
@(link_name="sgl_setup")
		setup :: proc "c" (desc: ^Desc) ---
@(link_name="sgl_shutdown")
		shutdown :: proc "c" () ---
	@(link_name="sgl_rad")
	rad :: proc "c" (deg: f32) -> f32 ---
	@(link_name="sgl_deg")
	deg :: proc "c" (radians: f32) -> f32 ---
@(link_name="sgl_defaults")
		defaults :: proc "c" () ---
	@(link_name="sgl_make_pipeline")
	make_pipeline :: proc "c" (desc: ^sg.Pipeline_Desc) -> Pipeline ---
@(link_name="sgl_load_pipeline")
		load_pipeline :: proc "c" (pip: Pipeline) ---
@(link_name="sgl_destroy_pipeline")
		destroy_pipeline :: proc "c" (pip: Pipeline) ---
@(link_name="sgl_begin_points")
		begin_points :: proc "c" () ---
@(link_name="sgl_begin_lines")
		begin_lines :: proc "c" () ---
@(link_name="sgl_begin_line_strip")
		begin_line_strip :: proc "c" () ---
@(link_name="sgl_begin_triangles")
		begin_triangles :: proc "c" () ---
@(link_name="sgl_begin_triangle_strip")
		begin_triangle_strip :: proc "c" () ---
@(link_name="sgl_begin_quads")
		begin_quads :: proc "c" () ---
@(link_name="sgl_end")
		end :: proc "c" () ---
@(link_name="sgl_push_matrix")
		push_matrix :: proc "c" () ---
@(link_name="sgl_pop_matrix")
		pop_matrix :: proc "c" () ---
@(link_name="sgl_matrix_mode_projection")
		matrix_mode_projection :: proc "c" () ---
@(link_name="sgl_matrix_mode_modelview")
		matrix_mode_modelview :: proc "c" () ---
@(link_name="sgl_matrix_mode_texture")
		matrix_mode_texture :: proc "c" () ---
@(link_name="sgl_load_identity")
		load_identity :: proc "c" () ---
@(link_name="sgl_translate")
		translate :: proc "c" (x, y, z: f32) ---
@(link_name="sgl_scale")
		scale :: proc "c" (x, y, z: f32) ---
@(link_name="sgl_rotate")
		rotate :: proc "c" (angle_radians, x, y, z: f32) ---
@(link_name="sgl_lookat")
		lookat :: proc "c" (eye_x, eye_y, eye_z, center_x, center_y, center_z, up_x, up_y, up_z: f32) ---
@(link_name="sgl_perspective")
		perspective :: proc "c" (fov_y_radians, aspect, z_near, z_far: f32) ---
@(link_name="sgl_viewport")
		viewport :: proc "c" (x, y, w, h: i32, origin_top_left: b8) ---
@(link_name="sgl_enable_texture")
		enable_texture :: proc "c" () ---
@(link_name="sgl_disable_texture")
		disable_texture :: proc "c" () ---
@(link_name="sgl_texture")
		texture :: proc "c" (view: sg.View, sampler: sg.Sampler) ---
@(link_name="sgl_c1i")
		c1i :: proc "c" (rgba: u32) ---
@(link_name="sgl_c3b")
		c3b :: proc "c" (r, g, b: u8) ---
@(link_name="sgl_c3f")
		c3f :: proc "c" (r, g, b: f32) ---
@(link_name="sgl_c4b")
		c4b :: proc "c" (r, g, b, a: u8) ---
@(link_name="sgl_c4f")
		c4f :: proc "c" (r, g, b, a: f32) ---
@(link_name="sgl_v2f")
		v2f :: proc "c" (x, y: f32) ---
@(link_name="sgl_v2f_c1i")
		v2f_c1i :: proc "c" (x, y: f32, rgba: u32) ---
@(link_name="sgl_v2f_c3b")
		v2f_c3b :: proc "c" (x, y: f32, r, g, b: u8) ---
@(link_name="sgl_v2f_c3f")
		v2f_c3f :: proc "c" (x, y: f32, r, g, b: f32) ---
@(link_name="sgl_v2f_c4b")
		v2f_c4b :: proc "c" (x, y: f32, r, g, b, a: u8) ---
@(link_name="sgl_v2f_c4f")
		v2f_c4f :: proc "c" (x, y: f32, r, g, b, a: f32) ---
@(link_name="sgl_v2t2f")
		v2t2f :: proc "c" (x, y, u, v: f32) ---
@(link_name="sgl_v3f")
		v3f :: proc "c" (x, y, z: f32) ---
@(link_name="sgl_v3f_c1i")
		v3f_c1i :: proc "c" (x, y, z: f32, rgba: u32) ---
@(link_name="sgl_v3f_c3b")
		v3f_c3b :: proc "c" (x, y, z: f32, r, g, b: u8) ---
@(link_name="sgl_v3f_c3f")
		v3f_c3f :: proc "c" (x, y, z: f32, r, g, b: f32) ---
@(link_name="sgl_v3f_c4b")
		v3f_c4b :: proc "c" (x, y, z: f32, r, g, b, a: u8) ---
@(link_name="sgl_v3f_c4f")
		v3f_c4f :: proc "c" (x, y, z: f32, r, g, b, a: f32) ---
@(link_name="sgl_v3t2f")
		v3t2f :: proc "c" (x, y, z, u, v: f32) ---
@(link_name="sgl_v2f_t2f")
		v2f_t2f :: proc "c" (x, y, u, v: f32) ---
@(link_name="sgl_v3f_t2f")
		v3f_t2f :: proc "c" (x, y, z, u, v: f32) ---
@(link_name="sgl_draw")
		draw :: proc "c" () ---
@(link_name="sgl_draw_layer")
		draw_layer :: proc "c" (layer: i32) ---
@(link_name="sgl_draw_ex")
		draw_ex :: proc "c" (layer, viewport_index: i32) ---
}
