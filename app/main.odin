package app

import "core:runtime"
import sdl "vendor:sdl3"
import sokol "native"

SMOKE_FRAMES :: #config(SMOKE_FRAMES, 0)

width, height: i32 = 480, 800
window: ^sdl.Window
gl: sdl.GLContext
frames: i32

@(export)
odin_app_Init :: proc "c" (state: ^rawptr, argc: i32, argv: [^]cstring) -> sdl.AppResult {
    context = runtime.default_context()
    // GLES 3.1 everywhere: sokol's GLES3 backend (compute + SSBO) on every
    // platform, and alpha-free opaque surfaces for clean mobile compositing.
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, transmute(i32) sdl.GL_CONTEXT_PROFILE_ES)
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)
    sdl.GL_SetAttribute(.ALPHA_SIZE, 0)

    window = sdl.CreateWindow("Odin + sokol_gfx", width, height, sdl.WindowFlags{.OPENGL, .RESIZABLE})
    if window == nil do return .FAILURE
    gl = sdl.GL_CreateContext(window)
    if gl == nil do return .FAILURE
    sdl.GL_MakeCurrent(window, gl)
    sdl.GL_SetSwapInterval(1)

    sokol.shim_init()
    return .CONTINUE
}

@(export)
odin_app_Iterate :: proc "c" (state: rawptr) -> sdl.AppResult {
    context = runtime.default_context()
    w, h: i32
    sdl.GetWindowSizeInPixels(window, &w, &h)
    if w == 0 || h == 0 do return .CONTINUE

    sokol.shim_compute()
    sokol.shim_begin_frame(w, h)
    sokol.shim_render()
    sokol.shim_end_frame()

    // Test harness: read the storage buffer straight through GL and assert
    // the compute results [11, 14, 17, 20].
    storage: [16]u8
    if sokol.shim_read_storage(raw_data(&storage)) {
        frames += 1
        sdl.Log("storage = %d %d %d %d", storage[0], storage[4], storage[8], storage[12])
        for i in 0..<4 {
            v := u32(storage[i*4])
            assert(v == u32(i)*3+11, "compute readback failed")
        }
    }

    sdl.GL_SwapWindow(window)

    when SMOKE_FRAMES > 0 {
        if frames >= SMOKE_FRAMES do return .SUCCESS
    }
    return .CONTINUE
}

@(export)
odin_app_Event :: proc "c" (state: rawptr, event: ^sdl.Event) -> sdl.AppResult {
    if event.type == .QUIT do return .SUCCESS
    return .CONTINUE
}

@(export)
odin_app_Quit :: proc "c" (state: rawptr, result: sdl.AppResult) {
    sokol.shim_shutdown()
    if gl != nil do sdl.GL_DestroyContext(gl)
    if window != nil do sdl.DestroyWindow(window)
    sdl.Quit()
}
