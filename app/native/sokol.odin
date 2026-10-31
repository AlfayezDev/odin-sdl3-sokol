package sokol

foreign import sokol_lib "sokol_impl"

foreign sokol_lib {
    shim_gl_attributes      :: proc() ---
    shim_init               :: proc(sdl_window: rawptr) ---
    shim_shutdown           :: proc() ---
    shim_frame_begin        :: proc() ---
    shim_dt                 :: proc() -> f32 ---
    shim_time               :: proc() -> f32 ---
    shim_begin_default_pass :: proc(width, height: i32) ---
    shim_render             :: proc() ---
    shim_read_pixels        :: proc(out: ^u8) -> b32 ---
    shim_end_frame          :: proc() ---
    shim_swap               :: proc() ---
}
