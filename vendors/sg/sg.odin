// Odin bindings for the vendored sokol_gfx.h (impl compiled in
// app/native/sokol_shim.c; symbols resolve at link time). Struct layouts
// mirror the C definitions exactly, canaries included, because sokol reads
// these structs by pointer.
package sg


// constants
INVALID_ID :: 0
MAX_COLOR_ATTACHMENTS :: 8
MAX_VERTEX_ATTRIBUTES :: 16
MAX_VERTEXBUFFER_BINDSLOTS :: 8
MAX_UNIFORMBLOCK_BINDSLOTS :: 8
MAX_VIEW_BINDSLOTS :: 32
MAX_SAMPLER_BINDSLOTS :: 12
MAX_TEXTURE_SAMPLER_PAIRS :: 32

// handle types
Buffer :: struct {id: u32}
Image :: struct {id: u32}
Sampler :: struct {id: u32}
Shader :: struct {id: u32}
Pipeline :: struct {id: u32}
View :: struct {id: u32}

Sampler_Type :: enum u32 {
	FILTERING,
	NONFILTERING,
	COMPARISON,
}

Image_Sample_Type :: enum u32 {
	FLOAT,
	DEPTH,
	SINT,
	UINT,
	UNFILTERABLE_FLOAT,
}

// enums (underlying C int)
Backend :: enum u32 {
	GLCORE,
	GLES3,
	D3D11,
	METAL_IOS,
	METAL_MACOS,
	METAL_SIMULATOR,
	WGPU,
	VULKAN,
	DUMMY,
}

Pixel_Format :: enum u32 {
	DEFAULT,
	NONE,
	R8,
	R8SN,
	R8UI,
	R8SI,
	R16,
	R16SN,
	R16UI,
	R16SI,
	R16F,
	RG8,
	RG8SN,
	RG8UI,
	RG8SI,
	R32UI,
	R32SI,
	R32F,
	RG16,
	RG16SN,
	RG16UI,
	RG16SI,
	RG16F,
	RGBA8,
	SRGB8A8,
	RGBA8SN,
	RGBA8UI,
	RGBA8SI,
	BGRA8,
	SBGR8A8,
	RGB10A2,
	RG11B10F,
	RGB9E5,
	RG32UI,
	RG32SI,
	RG32F,
	RGBA16,
	RGBA16SN,
	RGBA16UI,
	RGBA16SI,
	RGBA16F,
	RGBA32UI,
	RGBA32SI,
	RGBA32F,
	DEPTH,
	DEPTH_STENCIL,
}

Vertex_Format :: enum u32 {
	INVALID,
	FLOAT,
	FLOAT2,
	FLOAT3,
	FLOAT4,
	INT,
	INT2,
	INT3,
	INT4,
	UINT,
	UINT2,
	UINT3,
	UINT4,
	BYTE4,
	BYTE4N,
	UBYTE4,
	UBYTE4N,
	SHORT2,
	SHORT2N,
	USHORT2,
	USHORT2N,
	SHORT4,
	SHORT4N,
	USHORT4,
	USHORT4N,
	INT10_N2,
	UINT10_N2,
	HALF2,
	HALF4,
}

Vertex_Step :: enum u32 {
	PER_VERTEX,
	PER_INSTANCE,
}

Index_Type :: enum u32 {
	DEFAULT,
	NONE,
	UINT16,
	UINT32,
}

Image_Type :: enum u32 {
	_2D,
	CUBE,
	_3D,
	ARRAY,
}

Filter :: enum u32 {
	NEAREST,
	LINEAR,
}

Wrap :: enum u32 {
	REPEAT,
	CLAMP_TO_EDGE,
	CLAMP_TO_BORDER,
	MIRRORED_REPEAT,
}

Primitive_Type :: enum u32 {
	POINTS,
	LINES,
	LINE_STRIP,
	TRIANGLES,
	TRIANGLE_STRIP,
}

Compare_Func :: enum u32 {
	NEVER,
	LESS,
	EQUAL,
	LESS_EQUAL,
	GREATER,
	NOT_EQUAL,
	GREATER_EQUAL,
	ALWAYS,
}

Stencil_Op :: enum u32 {
	KEEP,
	ZERO,
	REPLACE,
	INCR_CLAMP,
	DECR_CLAMP,
	INVERT,
	INCR_WRAP,
	DECR_WRAP,
}

Blend_Factor :: enum u32 {
	ZERO,
	ONE,
	SRC_COLOR,
	ONE_MINUS_SRC_COLOR,
	SRC_ALPHA,
	ONE_MINUS_SRC_ALPHA,
	DST_COLOR,
	ONE_MINUS_DST_COLOR,
	DST_ALPHA,
	ONE_MINUS_DST_ALPHA,
	SRC_ALPHA_SATURATED,
	BLEND_COLOR,
	ONE_MINUS_BLEND_COLOR,
	BLEND_ALPHA,
	ONE_MINUS_BLEND_ALPHA,
	SRC1_COLOR,
	ONE_MINUS_SRC1_COLOR,
	SRC1_ALPHA,
	ONE_MINUS_SRC1_ALPHA,
}

Blend_Op :: enum u32 {
	ADD,
	SUBTRACT,
	REVERSE_SUBTRACT,
	MIN,
	MAX,
}

Load_Action :: enum u32 {
	CLEAR,
	LOAD,
	DONTCARE,
}

Store_Action :: enum u32 {
	STORE,
	DONTCARE,
}

Cull_Mode :: enum u32 {
	NONE,
	FRONT,
	BACK,
}

Face_Winding :: enum u32 {
	CCW,
	CW,
}

Shader_Stage :: enum u32 {
	NONE,
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

Uniform_Layout :: enum u32 {
	DEFAULT,
	NATIVE,
	STD140,
}

Uniform_Type :: enum u32 {
	INVALID,
	FLOAT,
	FLOAT2,
	FLOAT3,
	FLOAT4,
	INT,
	INT2,
	INT3,
	INT4,
	MAT4,
}

Attr_Base_Type :: enum u32 {
	UNDEFINED,
	FLOAT,
	SINT,
	UINT,
}

// setup descriptor (sg_desc)
Allocator :: struct {
	alloc_fn:  proc "c" (size: uint, user_data: rawptr) -> rawptr,
	free_fn:   proc "c" (ptr: rawptr, user_data: rawptr),
	user_data: rawptr,
}

Log_Func :: #type proc "c" (tag: cstring, log_level: u32, log_item_id: u32, message_or_null: cstring, line_nr: u32, filename_or_null: cstring, user_data: rawptr)

Logger :: struct {
	func:      Log_Func,
	user_data: rawptr,
}

Environment_Defaults :: struct {
	color_format: Pixel_Format,
	depth_format: Pixel_Format,
	sample_count: i32,
}

Metal_Environment :: struct {
	device: rawptr,
}

D3D11_Environment :: struct {
	device:        rawptr,
	device_context: rawptr,
}

Wgpu_Environment :: struct {
	device: rawptr,
}

Vulkan_Environment :: struct {
	instance:           rawptr,
	physical_device:    rawptr,
	device:             rawptr,
	queue:              rawptr,
	queue_family_index: u32,
}

Environment :: struct {
	defaults: Environment_Defaults,
	metal:    Metal_Environment,
	d3d11:    D3D11_Environment,
	wgpu:     Wgpu_Environment,
	vulkan:   Vulkan_Environment,
}

D3D11_Desc :: struct {
	shader_debugging: b8,
}

Metal_Desc :: struct {
	force_managed_storage_mode:                  b8,
	use_command_buffer_with_retained_references: b8,
}

Wgpu_Desc :: struct {
	disable_bindgroups_cache: b8,
	bindgroups_cache_size:    i32,
}

Vulkan_Desc :: struct {
	copy_staging_buffer_size:     i32,
	transient_staging_buffer_size: i32,
	descriptor_buffer_size:       i32,
}

Desc :: struct {
	_start_canary:         u32,
	buffer_pool_size:      i32,
	image_pool_size:       i32,
	sampler_pool_size:     i32,
	shader_pool_size:      i32,
	pipeline_pool_size:    i32,
	view_pool_size:        i32,
	uniform_buffer_size:   i32,
	max_commit_listeners:  i32,
	disable_validation:    b8,
	enforce_portable_limits: b8,
	d3d11:                 D3D11_Desc,
	metal:                 Metal_Desc,
	wgpu:                  Wgpu_Desc,
	vulkan:                Vulkan_Desc,
	allocator:             Allocator,
	logger:                Logger,
	environment:           Environment,
	_end_canary:           u32,
}

// structs
Range :: struct {
	ptr: rawptr,
	size: uint,
}

range_of :: proc(p: rawptr, byte_size: uint) -> Range {
	return Range{ptr = p, size = byte_size}
}

Color :: struct {
	r, g, b, a: f32,
}

Buffer_Usage :: struct {
	vertex_buffer: b8,
	index_buffer: b8,
	storage_buffer: b8,
	staging_buffer: b8,
	staging_index_buffer: b8,
	write_unsealed: b8,
	write_transient: b8,
	copy_src: b8,
	copy_dst: b8,
}

Buffer_Desc :: struct {
	_start_canary: u32,
	size:          uint,
	usage:         Buffer_Usage,
	data:          Range,
	label:         cstring,
	gl_buffer:     u32,
	mtl_buffer:    rawptr,
	d3d11_buffer:  rawptr,
	wgpu_buffer:   rawptr,
	_end_canary:   u32,
}

Image_Usage :: struct {
	storage_image: b8,
	color_attachment: b8,
	resolve_attachment: b8,
	depth_stencil_attachment: b8,
	write_unsealed: b8,
	write_transient: b8,
	copy_src: b8,
	copy_dst: b8,
}

Image_Desc :: struct {
	_start_canary:    u32,
	type:             Image_Type,
	usage:            Image_Usage,
	width:            i32,
	height:           i32,
	num_slices:       i32,
	num_mipmaps:      i32,
	pixel_format:     Pixel_Format,
	sample_count:     i32,
	data:             Range,
	label:            cstring,
	gl_texture:       u32,
	gl_texture_target: u32,
	mtl_texture:      rawptr,
	d3d11_texture:    rawptr,
	wgpu_texture:     rawptr,
	_end_canary:      u32,
}

Sampler_Desc :: struct {
	_start_canary:  u32,
	min_filter:     Filter,
	mag_filter:     Filter,
	mipmap_filter:  Filter,
	wrap_u:         Wrap,
	wrap_v:         Wrap,
	wrap_w:         Wrap,
	min_lod:        f32,
	max_lod:        f32,
	border_color:   u32, // sg_border_color (unused here)
	compare:        Compare_Func,
	max_anisotropy: u32,
	label:          cstring,
	gl_sampler:     u32,
	mtl_sampler:    rawptr,
	d3d11_sampler:  rawptr,
	wgpu_sampler:   rawptr,
	_end_canary:    u32,
}

Shader_Function :: struct {
	source:        cstring,
	bytecode:      Range,
	entry:         cstring,
	d3d11_target:  cstring,
	d3d11_filepath: cstring,
}

Shader_Vertex_Attr :: struct {
	base_type:      Attr_Base_Type,
	glsl_name:      cstring,
	hlsl_sem_name:  cstring,
	hlsl_sem_index: u8,
}

Glsl_Shader_Uniform :: struct {
	type:        Uniform_Type,
	array_count: u16,
	glsl_name:   cstring,
}

Shader_Uniform_Block :: struct {
	stage:                Shader_Stage,
	size:                 u32,
	hlsl_register_b_n:    u8,
	msl_buffer_n:         u8,
	wgsl_group0_binding_n: u8,
	spirv_set0_binding_n: u8,
	layout:               Uniform_Layout,
	glsl_uniforms:        [MAX_UNIFORMBLOCK_MEMBERS]Glsl_Shader_Uniform,
}

MAX_UNIFORMBLOCK_MEMBERS :: 16

Shader_Desc :: struct {
	_start_canary:          u32,
	vertex_func:            Shader_Function,
	fragment_func:          Shader_Function,
	compute_func:           Shader_Function,
	attrs:                  [MAX_VERTEX_ATTRIBUTES]Shader_Vertex_Attr,
	uniform_blocks:         [MAX_UNIFORMBLOCK_BINDSLOTS]Shader_Uniform_Block,
	views:                  [MAX_VIEW_BINDSLOTS]Shader_View,
	samplers:               [MAX_SAMPLER_BINDSLOTS]Shader_Sampler,
	texture_sampler_pairs:  [MAX_TEXTURE_SAMPLER_PAIRS]Shader_Texture_Sampler_Pair,
	mtl_threads_per_threadgroup: Mtl_Threads_Per_Threadgroup,
	label:                  cstring,
	_end_canary:            u32,
}

Shader_Texture_View :: struct {
	stage:             Shader_Stage,
	image_type:        Image_Type,
	sample_type:       Image_Sample_Type,
	multisampled: b8,
	hlsl_register_t_n: u8,
	msl_texture_n:     u8,
	wgsl_group1_binding_n: u8,
	spirv_set1_binding_n: u8,
}

Shader_Storage_Buffer_View :: struct {
	stage:             Shader_Stage,
	readonly: b8,
	hlsl_register_t_n: u8,
	hlsl_register_u_n: u8,
	msl_buffer_n:      u8,
	wgsl_group1_binding_n: u8,
	spirv_set1_binding_n: u8,
	glsl_binding_n:    u8,
}

Shader_Storage_ImageView :: struct {
	stage:             Shader_Stage,
	image_type:        Image_Type,
	access_format:     Pixel_Format,
	writeonly: b8,
	hlsl_register_u_n: u8,
	msl_texture_n:     u8,
	wgsl_group1_binding_n: u8,
	spirv_set1_binding_n: u8,
	glsl_binding_n:    u8,
}

Shader_View :: struct {
	texture:         Shader_Texture_View,
	storage_buffer:  Shader_Storage_Buffer_View,
	storage_image:   Shader_Storage_ImageView,
}

Shader_Sampler :: struct {
	stage:                Shader_Stage,
	sampler_type:         Sampler_Type,
	hlsl_register_s_n:    u8,
	msl_sampler_n:        u8,
	wgsl_group1_binding_n: u8,
	spirv_set1_binding_n: u8,
}

Shader_Texture_Sampler_Pair :: struct {
	stage:        Shader_Stage,
	view_slot:    u8,
	sampler_slot: u8,
	glsl_name:    cstring,
}

Mtl_Threads_Per_Threadgroup :: struct {
	x, y, z: i32,
}

Vertex_Attr_State :: struct {
	buffer_index: i32,
	offset:       i32,
	format:       Vertex_Format,
}

Vertex_Buffer_Layout_State :: struct {
	stride:    i32,
	step_func: Vertex_Step,
	step_rate: i32,
}

Vertex_Layout_State :: struct {
	buffers: [MAX_VERTEXBUFFER_BINDSLOTS]Vertex_Buffer_Layout_State,
	attrs:   [MAX_VERTEX_ATTRIBUTES]Vertex_Attr_State,
}

Blend_State :: struct {
	enabled: b8,
	src_factor_rgb:   Blend_Factor,
	dst_factor_rgb:   Blend_Factor,
	op_rgb:           Blend_Op,
	src_factor_alpha: Blend_Factor,
	dst_factor_alpha: Blend_Factor,
	op_alpha:         Blend_Op,
}

Stencil_Face_State :: struct {
	compare:       Compare_Func,
	fail_op:       Stencil_Op,
	depth_fail_op: Stencil_Op,
	pass_op:       Stencil_Op,
}

Stencil_State :: struct {
	enabled: b8,
	front:     Stencil_Face_State,
	back:      Stencil_Face_State,
	read_mask: u8,
	write_mask: u8,
	ref:       u8,
}

Depth_State :: struct {
	pixel_format:     Pixel_Format,
	compare:          Compare_Func,
	write_enabled: b8,
	bias:             f32,
	bias_slope_scale: f32,
	bias_clamp:       f32,
}

Color_Target_State :: struct {
	pixel_format: Pixel_Format,
	write_mask:   u8, // sg_color_mask
	blend:        Blend_State,
}

Pipeline_Desc :: struct {
	_start_canary: u32,
	compute: b8,
	shader:        Shader,
	layout:        Vertex_Layout_State,
	depth:         Depth_State,
	stencil:       Stencil_State,
	color_count:   i32,
	colors:        [MAX_COLOR_ATTACHMENTS]Color_Target_State,
	primitive_type: Primitive_Type,
	index_type:    Index_Type,
	cull_mode:     Cull_Mode,
	face_winding:  Face_Winding,
	sample_count:  i32,
	blend_color:   Color,
	alpha_to_coverage_enabled: b8,
	label:         cstring,
	_end_canary:   u32,
}

Texture_View_Range :: struct {
	base:  i32,
	count: i32,
}

Texture_View_Desc :: struct {
	image:     Image,
	mip_levels: Texture_View_Range,
	slices:    Texture_View_Range,
}

Buffer_View_Desc :: struct {
	buffer: Buffer,
	offset: i32,
}

Image_View_Desc :: struct {
	image:    Image,
	mip_level: i32,
	slice:    i32,
}

View_Desc :: struct {
	_start_canary:           u32,
	texture:                 Texture_View_Desc,
	storage_buffer:          Buffer_View_Desc,
	storage_image:           Image_View_Desc,
	color_attachment:        Image_View_Desc,
	resolve_attachment:      Image_View_Desc,
	depth_stencil_attachment: Image_View_Desc,
	label:                   cstring,
	_end_canary:             u32,
}

Attachments :: struct {
	colors:        [MAX_COLOR_ATTACHMENTS]View,
	resolves:      [MAX_COLOR_ATTACHMENTS]View,
	depth_stencil: View,
}

Gl_Swapchain :: struct {
	framebuffer: u32,
}

Metal_Swapchain :: struct {
	current_drawable:      rawptr,
	depth_stencil_texture: rawptr,
	msaa_color_texture:    rawptr,
}

D3D11_Swapchain :: struct {
	render_view:       rawptr,
	resolve_view:      rawptr,
	depth_stencil_view: rawptr,
}

Wgpu_Swapchain :: struct {
	render_view:       rawptr,
	resolve_view:      rawptr,
	depth_stencil_view: rawptr,
}

Vulkan_Swapchain :: struct {
	render_image:               rawptr,
	render_view:                rawptr,
	resolve_image:              rawptr,
	resolve_view:               rawptr,
	depth_stencil_image:        rawptr,
	depth_stencil_view:         rawptr,
	render_finished_semaphore:  rawptr,
	present_complete_semaphore: rawptr,
}

Swapchain :: struct {
	invalid: b8,
	width:        i32,
	height:       i32,
	sample_count: i32,
	color_format: Pixel_Format,
	depth_format: Pixel_Format,
	metal:        Metal_Swapchain,
	d3d11:        D3D11_Swapchain,
	wgpu:         Wgpu_Swapchain,
	vulkan:       Vulkan_Swapchain,
	gl:           Gl_Swapchain,
}

Color_Attachment_Action :: struct {
	load_action:  Load_Action,
	store_action: Store_Action,
	clear_value:  Color,
}

Depth_Attachment_Action :: struct {
	load_action:  Load_Action,
	store_action: Store_Action,
	clear_value:  f32,
}

Stencil_Attachment_Action :: struct {
	load_action:  Load_Action,
	store_action: Store_Action,
	clear_value:  u8,
}

Pass_Action :: struct {
	colors:  [MAX_COLOR_ATTACHMENTS]Color_Attachment_Action,
	depth:   Depth_Attachment_Action,
	stencil: Stencil_Attachment_Action,
}

Pass :: struct {
	_start_canary: u32,
	compute: b8,
	action:        Pass_Action,
	attachments:   Attachments,
	swapchain:     Swapchain,
	label:         cstring,
	_end_canary:   u32,
}

Bindings :: struct {
	_start_canary:         u32,
	vertex_buffers:        [MAX_VERTEXBUFFER_BINDSLOTS]Buffer,
	vertex_buffer_offsets: [MAX_VERTEXBUFFER_BINDSLOTS]i32,
	index_buffer:          Buffer,
	index_buffer_offset:   i32,
	views:                 [MAX_VIEW_BINDSLOTS]View,
	samplers:              [MAX_SAMPLER_BINDSLOTS]Sampler,
	_end_canary:           u32,
}

Write_Buffer_Source :: struct {
	data:   Range,
	offset: uint,
}

Buffer_Location :: struct {
	buffer: Buffer,
	offset: uint,
}

Write_Buffer_Desc :: struct {
	src:  Write_Buffer_Source,
	dst:  Buffer_Location,
	size: uint,
}

Write_Image_Source :: struct {
	data:           Range,
	offset:         uint,
	bytes_per_row:  i32,
	bytes_per_slice: i32,
}

Image_Location :: struct {
	image:    Image,
	mip_level: i32,
	x:        i32,
	y:        i32,
	slice:    i32,
}

Image_Extent :: struct {
	width:      i32,
	height:     i32,
	num_slices: i32,
}

Write_Image_Desc :: struct {
	src:  Write_Image_Source,
	dst:  Image_Location,
	size: Image_Extent,
}

// functions
foreign {
@(link_name="sg_setup")
		setup :: proc "c" (desc: rawptr) ---
@(link_name="sg_shutdown")
		shutdown :: proc "c" () ---
	@(link_name="sg_query_backend")
	query_backend :: proc "c" () -> Backend ---
	@(link_name="sg_query_buffer_state")
	query_buffer_state :: proc "c" (buf: Buffer) -> i32 ---
	@(link_name="sg_query_image_state")
	query_image_state :: proc "c" (img: Image) -> i32 ---
	@(link_name="sg_make_buffer")
	make_buffer :: proc "c" (desc: ^Buffer_Desc) -> Buffer ---
	@(link_name="sg_make_image")
	make_image :: proc "c" (desc: ^Image_Desc) -> Image ---
	@(link_name="sg_make_sampler")
	make_sampler :: proc "c" (desc: ^Sampler_Desc) -> Sampler ---
	@(link_name="sg_make_shader")
	make_shader :: proc "c" (desc: ^Shader_Desc) -> Shader ---
	@(link_name="sg_make_pipeline")
	make_pipeline :: proc "c" (desc: ^Pipeline_Desc) -> Pipeline ---
	@(link_name="sg_make_view")
	make_view :: proc "c" (desc: ^View_Desc) -> View ---
@(link_name="sg_destroy_buffer")
		destroy_buffer :: proc "c" (buf: Buffer) ---
@(link_name="sg_destroy_image")
		destroy_image :: proc "c" (img: Image) ---
@(link_name="sg_destroy_sampler")
		destroy_sampler :: proc "c" (smp: Sampler) ---
@(link_name="sg_destroy_shader")
		destroy_shader :: proc "c" (shd: Shader) ---
@(link_name="sg_destroy_pipeline")
		destroy_pipeline :: proc "c" (pip: Pipeline) ---
@(link_name="sg_destroy_view")
		destroy_view :: proc "c" (view: View) ---
	@(link_name="sg_alloc_image")
	alloc_image :: proc "c" () -> Image ---
	@(link_name="sg_alloc_view")
	alloc_view :: proc "c" () -> View ---
@(link_name="sg_init_image")
		init_image :: proc "c" (img: Image, desc: ^Image_Desc) ---
@(link_name="sg_init_view")
		init_view :: proc "c" (view: View, desc: ^View_Desc) ---
@(link_name="sg_uninit_image")
		uninit_image :: proc "c" (img: Image) ---
@(link_name="sg_uninit_view")
		uninit_view :: proc "c" (view: View) ---
@(link_name="sg_begin_pass")
		begin_pass :: proc "c" (pass: ^Pass) ---
@(link_name="sg_end_pass")
		end_pass :: proc "c" () ---
@(link_name="sg_commit")
		commit :: proc "c" () ---
@(link_name="sg_apply_pipeline")
		apply_pipeline :: proc "c" (pip: Pipeline) ---
@(link_name="sg_apply_bindings")
		apply_bindings :: proc "c" (bindings: ^Bindings) ---
@(link_name="sg_apply_uniforms")
		apply_uniforms :: proc "c" (ub_slot: i32, data: ^Range) ---
@(link_name="sg_draw")
		draw :: proc "c" (base_element, num_elements, num_instances: i32) ---
@(link_name="sg_apply_viewport")
		apply_viewport :: proc "c" (x, y, w, h: i32, origin_top_left: b8) ---
@(link_name="sg_write_buffer_transient")
		write_buffer_transient :: proc "c" (desc: ^Write_Buffer_Desc) ---
@(link_name="sg_write_image_transient")
		write_image_transient :: proc "c" (desc: ^Write_Image_Desc) ---
}
