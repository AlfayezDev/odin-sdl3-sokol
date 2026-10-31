package app

import "core:fmt"
import "core:runtime"
import sdl "vendor:sdl3"
import sokol "native"

SMOKE_FRAMES :: #config(SMOKE_FRAMES, 0)
SAMPLE_ID :: #config(SAMPLE_ID, 0)

width, height: i32 = 480, 800
window: ^sdl.Window
gl: sdl.GLContext
frames: i32

// The triangle (sample 0) render verification: colors at the three vertices
// (nudged 1% inward) and at screen center (0,0), whose barycentric mix is
// red 0.5, green 0.25, blue 0.25. Tolerance covers rasterizer edge effects.
verify_pixels :: proc(pixels: [16]u8) {
    corners := [4][3]f32{
        {1.0, 0.0, 0.0},
        {0.0, 1.0, 0.0},
        {0.0, 0.0, 1.0},
        {0.5, 0.25, 0.25},
    }
    sdl.Log("px: %d %d %d | %d %d %d | %d %d %d | %d %d %d",
        pixels[0], pixels[1], pixels[2], pixels[4], pixels[5], pixels[6],
        pixels[8], pixels[9], pixels[10], pixels[12], pixels[13], pixels[14])
    for i in 0..<4 {
        for c in 0..<3 {
            // i32 math: u8 would overflow on expect+12 near 255
            expect := i32(corners[i][c] * 255.0 + 0.5)
            got := i32(pixels[i*4+c])
            assert(
                got >= expect - 12 && got <= expect + 12,
                fmt.tprintf("pixel %d channel %d: got %d want ~%d", i, c, got, expect),
            )
        }
    }
}

@(export)
odin_app_Init :: proc "c" (state: ^rawptr, argc: i32, argv: [^]cstring) -> sdl.AppResult {
    context = runtime.default_context()
    sokol.shim_gl_attributes()

    window = sdl.CreateWindow("Odin + sokol_gfx", width, height, sdl.WindowFlags{.OPENGL, .RESIZABLE})
    if window == nil do return .FAILURE

    // SDL owns the GL context everywhere: desktop GL 4.1 core / Android+iOS
    // ES 3.0, versions requested via shim_gl_attributes.
    gl = sdl.GL_CreateContext(window)
    if gl == nil do return .FAILURE
    sdl.GL_MakeCurrent(window, gl)

    sokol.shim_init(window)
    sokol.sample_init(SAMPLE_ID)
    return .CONTINUE
}

@(export)
odin_app_Iterate :: proc "c" (state: rawptr) -> sdl.AppResult {
    context = runtime.default_context()
    w, h: i32
    sdl.GetWindowSizeInPixels(window, &w, &h)
    if w == 0 || h == 0 do return .CONTINUE

    sokol.shim_frame_begin()

    if SAMPLE_ID == 0 {
        sokol.shim_begin_default_pass(w, h)
        sokol.shim_render()

        pixels: [16]u8
        if sokol.shim_read_pixels(raw_data(&pixels)) {
            frames += 1
            verify_pixels(pixels)
        }
        sokol.shim_end_frame()
    } else {
        sokol.sample_frame(SAMPLE_ID, w, h)

        // smoke harness: the frame must leave non-clear content at screen center
        pixel: [16]u8
        if sokol.shim_read_pixels(raw_data(&pixel)) {
            assert(pixel[0] != 0 || pixel[1] != 0 || pixel[2] != 0, "sample rendered nothing")
        }
        frames += 1
    }

    sokol.shim_swap()

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
    sokol.sample_shutdown(SAMPLE_ID)
    sokol.shim_shutdown()
    if window != nil do sdl.DestroyWindow(window)
    sdl.Quit()
}
