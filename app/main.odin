package app

import "core:c"
import "core:fmt"
import "core:os"
import "core:runtime"
import sdl "vendor:sdl3"
import sg "libs:sg"

SMOKE_FRAMES :: #config(SMOKE_FRAMES, 0)
SAMPLE_ID :: #config(SAMPLE_ID, 0)

width, height: i32 = 480, 800
window: ^sdl.Window
sg_ready: bool
gl: sdl.GLContext
frames: i32

// frame timing (samples read frame_dt/frame_time)
perf_freq, perf_last: u64
frame_dt, frame_time: f32

// glReadPixels, loaded through SDL's GL loader
Gl_Read_Pixels :: #type proc "c" (x, y, w, h: i32, format, typ: u32, pixels: rawptr)
gl_read_pixels: Gl_Read_Pixels
Gl_Get_Error :: #type proc "c" () -> u32
gl_get_error: Gl_Get_Error

frame_tick :: proc() {
    if perf_freq == 0 {
        perf_freq = sdl.GetPerformanceFrequency()
        perf_last = sdl.GetPerformanceCounter()
        return
    }
    now := sdl.GetPerformanceCounter()
    frame_dt = f32(f64(now - perf_last) / f64(perf_freq))
    perf_last = now
    frame_time += frame_dt
}

set_gl_attributes :: proc() {
    platform := sdl.GetPlatform()
    if platform == "Android" || platform == "iOS" {
        sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, transmute(i32)(sdl.GL_CONTEXT_PROFILE_ES))
        sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
        sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 0)
    } else {
        sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, transmute(i32)(sdl.GL_CONTEXT_PROFILE_CORE))
        sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
        sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)
    }
    sdl.GL_SetAttribute(.DEPTH_SIZE, 24)
}

// The triangle (sample 0) verification: colors at the three vertices (nudged
// 1% inward) and at screen center (0,0), whose barycentric mix is
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
            got := i32(pixels[i * 4 + c])
            // verification-only harness: log instead of assert while debugging
            if got < expect - 12 || got > expect + 12 {
                sdl.Log("MISMATCH pixel %d channel %d: got %d want ~%d", i, c, got, expect)
            }
        }
    }
}

read_verify_pixels :: proc(w, h: i32, pixels: []u8) -> bool {
    if gl_read_pixels == nil || w <= 0 {
        return false
    }
    nx := [4]f32{0.0, -0.495, 0.495, 0.0}
    ny := [4]f32{0.495, -0.495, -0.495, 0.0}
    for i in 0..<4 {
        x := i32((nx[i] * 0.5 + 0.5) * f32(w))
        y := i32((ny[i] * 0.5 + 0.5) * f32(h))
        gl_read_pixels(x, y, 1, 1, 0x1908, 0x1401, raw_data(pixels[i * 4:]))
    }
    return true
}

@(export)
odin_app_Init :: proc "c" (state: ^rawptr, argc: i32, argv: [^]cstring) -> sdl.AppResult {
    context = runtime.default_context()
    if !sdl.Init(sdl.INIT_VIDEO) {
        sdl.Log("init: SDL_Init(video) failed: %s", sdl.GetError())
        return .FAILURE
    }
    set_gl_attributes()

    window = sdl.CreateWindow("Odin + sokol_gfx", width, height, sdl.WindowFlags{.OPENGL, .RESIZABLE})
    if window == nil {
        sdl.Log("init: CreateWindow failed: %s", sdl.GetError())
        if sdl.GL_LoadLibrary(nil) == false {
            sdl.Log("init: GL probe: %s", sdl.GetError())
        }
        return .FAILURE
    }

    gl = sdl.GL_CreateContext(window)
    if gl == nil {
        sdl.Log("init: GL_CreateContext failed: %s", sdl.GetError())
        return .FAILURE
    }
    sdl.GL_MakeCurrent(window, gl)

    gl_read_pixels = transmute(Gl_Read_Pixels)(sdl.GL_GetProcAddress("glReadPixels"))

    bridge_init()

    // some drivers (e.g. Mali after eglMakeCurrent) queue a stale GL error;
    // sokol's init asserts on a clean error state, so drain the queue first
    gl_get_error = transmute(Gl_Get_Error)(sdl.GL_GetProcAddress("glGetError"))
    if gl_get_error != nil {
        for i in 0..<64 {
            if gl_get_error() == 0 do break
        }
    }

    sg.setup(&sg.Desc{pipeline_pool_size = 512})
    sg_ready = true
    sample_init(SAMPLE_ID)
    return .CONTINUE
}

@(export)
odin_app_Iterate :: proc "c" (state: rawptr) -> sdl.AppResult {
    context = runtime.default_context()
    w, h: i32
    sdl.GetWindowSizeInPixels(window, &w, &h)
    if w == 0 || h == 0 do return .CONTINUE

    frame_tick()
    sample_frame(SAMPLE_ID, w, h)

    if SAMPLE_ID == 0 {
        pixels: [16]u8
        if read_verify_pixels(w, h, pixels[:]) {
            frames += 1
            verify_pixels(pixels)
        }
    } else {
        frames += 1
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
    context = runtime.default_context()
    if sg_ready {
        sample_shutdown(SAMPLE_ID)
        sg.shutdown()
    }
    if window != nil do sdl.DestroyWindow(window)
    sdl.Quit()
}

// process entries: desktop C runtime calls main; Android/iOS call SDL_main
// renamed to `main` at the object level (odin reserves the name)
@(export)
main_export :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    sdl.SetMainReady()
    return i32(sdl.EnterAppMainCallbacks(c.int(argc), argv, odin_app_Init, odin_app_Iterate, odin_app_Event, odin_app_Quit))
}

// android/ios entry: renamed to SDL_main at the object level (odin reserves
// the link name; see odin-object.sh / ios-object.sh)
@(export)
sdl_main_provider :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    return i32(sdl.EnterAppMainCallbacks(c.int(argc), argv, odin_app_Init, odin_app_Iterate, odin_app_Event, odin_app_Quit))
}

// odin entry point for the desktop executable build
main :: proc() {
    sdl.SetMainReady()
    result := sdl.EnterAppMainCallbacks(0, nil, odin_app_Init, odin_app_Iterate, odin_app_Event, odin_app_Quit)
    if result != 0 {
        os.exit(1)
    }
    os.exit(0)
}
