package sokol

foreign import sokol_lib "sokol_impl"

foreign sokol_lib {
    shim_init                :: proc() ---
    shim_shutdown            :: proc() ---
    shim_begin_frame       :: proc(width, height: i32) ---
    shim_compute             :: proc() ---
    shim_render              :: proc() ---
    shim_read_pixels         :: proc(out: ^u8) -> b32 ---
    shim_read_storage        :: proc(out: ^u8) -> b32 ---
    shim_end_frame           :: proc() ---
}
