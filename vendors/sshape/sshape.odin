// Odin bindings for the vendored sokol_shape.h (impl compiled in
// app/native/sokol_shim.c via SOKOL_IMPL).
package sshape

import sg "libs:sg"

MAX_VERTEX_SIZE :: 24

Mat4 :: struct {
	m: [4][4]f32, // C float[4][4]: rows of columns, indexed m[row][col]
}

Range :: struct {
	ptr:  rawptr,
	size: uint,
}

Optional_Components :: struct {
	normals: b8,
	texcoords: b8,
	colors: b8,
}

Element_Range :: struct {
	base_element: i32,
	num_elements: i32,
}

Sizes_Item :: struct {
	num:  u32,
	size: u32,
}

Sizes :: struct {
	vertices: Sizes_Item,
	indices:  Sizes_Item,
}

Buffer_State :: struct {
	buffer:      Range,
	data_size:   uint,
	shape_offset: uint,
}

State :: struct {
	valid: b8,
	disable:  Optional_Components,
	vertices: Buffer_State,
	indices:  Buffer_State,
}

Plane :: struct {
	width:  f32,
	depth:  f32,
	tiles:  u16,
	color:  u32,
	random_colors: b8,
	merge: b8,
	transform: Mat4,
}

Box :: struct {
	width:  f32,
	height: f32,
	depth:  f32,
	tiles:  u16,
	color:  u32,
	random_colors: b8,
	merge: b8,
	transform: Mat4,
}

Sphere :: struct {
	radius: f32,
	slices: u16,
	stacks: u16,
	color:  u32,
	random_colors: b8,
	merge: b8,
	transform: Mat4,
}

Cylinder :: struct {
	radius: f32,
	height: f32,
	slices: u16,
	stacks: u16,
	color:  u32,
	random_colors: b8,
	merge: b8,
	transform: Mat4,
}

Torus :: struct {
	radius:     f32,
	ring_radius: f32,
	sides:      u16,
	rings:      u16,
	color:      u32,
	random_colors: b8,
	merge: b8,
	transform:  Mat4,
}

range_of :: proc(p: rawptr, byte_size: uint) -> Range {
	return Range{ptr = p, size = byte_size}
}

foreign {
@(link_name="sshape_build_plane")
		build_plane :: proc "c" (state: ^State, params: ^Plane) ---
@(link_name="sshape_build_box")
		build_box :: proc "c" (state: ^State, params: ^Box) ---
@(link_name="sshape_build_sphere")
		build_sphere :: proc "c" (state: ^State, params: ^Sphere) ---
@(link_name="sshape_build_cylinder")
		build_cylinder :: proc "c" (state: ^State, params: ^Cylinder) ---
@(link_name="sshape_build_torus")
		build_torus :: proc "c" (state: ^State, params: ^Torus) ---
	@(link_name="sshape_element_range")
	element_range :: proc "c" (state: ^State) -> Element_Range ---
	@(link_name="sshape_vertex_buffer_desc")
	vertex_buffer_desc :: proc "c" (state: ^State) -> sg.Buffer_Desc ---
	@(link_name="sshape_index_buffer_desc")
	index_buffer_desc :: proc "c" (state: ^State) -> sg.Buffer_Desc ---
	@(link_name="sshape_vertex_buffer_layout_state")
	vertex_buffer_layout_state :: proc "c" (state: ^State) -> sg.Vertex_Buffer_Layout_State ---
	@(link_name="sshape_position_vertex_attr_state")
	position_vertex_attr_state :: proc "c" (state: ^State) -> sg.Vertex_Attr_State ---
	@(link_name="sshape_normal_vertex_attr_state")
	normal_vertex_attr_state :: proc "c" (state: ^State) -> sg.Vertex_Attr_State ---
	@(link_name="sshape_texcoord_vertex_attr_state")
	texcoord_vertex_attr_state :: proc "c" (state: ^State) -> sg.Vertex_Attr_State ---
	@(link_name="sshape_color_vertex_attr_state")
	color_vertex_attr_state :: proc "c" (state: ^State) -> sg.Vertex_Attr_State ---
}
