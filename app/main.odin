package app

import "core:c"
import "base:runtime"
import sdl "vendor:sdl3"
import sg "libs:sg"
import shaders "libs:shaders"

width, height: i32 = 480, 800
window: ^sdl.Window
gl: sdl.GLContext
sg_ready: bool

// glGetError, loaded through SDL's GL loader
Gl_Get_Error :: #type proc "c" () -> u32
gl_get_error: Gl_Get_Error

triangle_bind: sg.Bindings
triangle_pip: sg.Pipeline
triangle_pass: sg.Pass_Action

triangle_vertices := [18]f32{
    0.0, 0.5, 0.5, 1.0, 0.0, 0.0,
    -0.5, -0.5, 0.5, 0.0, 1.0, 0.0,
    0.5, -0.5, 0.5, 0.0, 0.0, 1.0,
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

triangle_init :: proc() {
    shd := shaders.triangle_triangle_shader_desc(sg.query_backend())
    triangle_bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&triangle_vertices), size_of(triangle_vertices)),
        label = "triangle-vertices",
    })
    triangle_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&shd),
        layout = {
            attrs = {
                shaders.triangle_ATTR_triangle_position = {format = .FLOAT3},
                shaders.triangle_ATTR_triangle_color0 = {format = .FLOAT3},
            },
        },
        label = "triangle-pipeline",
    })
    triangle_pass = {colors = {0 = {load_action = .CLEAR, clear_value = {0.08, 0.22, 0.43, 1.0}}}}
}

triangle_frame :: proc(w, h: i32) {
    sg.begin_pass(&sg.Pass{action = triangle_pass, swapchain = {width = w, height = h}})
    sg.apply_pipeline(triangle_pip)
    sg.apply_bindings(&triangle_bind)
    sg.draw(0, 3, 1)
    sg.end_pass()
    sg.commit()
}

triangle_shutdown :: proc() {
    sg.destroy_pipeline(triangle_pip)
    sg.destroy_buffer(triangle_bind.vertex_buffers[0])
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
        return .FAILURE
    }

    gl = sdl.GL_CreateContext(window)
    if gl == nil {
        sdl.Log("init: GL_CreateContext failed: %s", sdl.GetError())
        return .FAILURE
    }
    sdl.GL_MakeCurrent(window, gl)

    // some drivers queue a stale GL error after eglMakeCurrent; sokol's init
    // asserts on a clean error state, so drain the queue first
    gl_get_error = transmute(Gl_Get_Error)(sdl.GL_GetProcAddress("glGetError"))
    if gl_get_error != nil {
        for _ in 0..<64 {
            if gl_get_error() == 0 do break
        }
    }

    sg.setup(&sg.Desc{})
    sg_ready = true
    triangle_init()
    bridge_init()
    return .CONTINUE
}

@(export)
odin_app_Iterate :: proc "c" (state: rawptr) -> sdl.AppResult {
    context = runtime.default_context()
    w, h: i32
    sdl.GetWindowSizeInPixels(window, &w, &h)
    if w == 0 || h == 0 do return .CONTINUE

    triangle_frame(w, h)
    sdl.GL_SwapWindow(window)
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
        triangle_shutdown()
        sg.shutdown()
    }
    if window != nil do sdl.DestroyWindow(window)
    sdl.Quit()
}

// Android/iOS entry: renamed to SDL_main at the object level (Odin reserves
// the name; see the android/ios build scripts).
@(export)
sdl_main_provider :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    return i32(sdl.EnterAppMainCallbacks(c.int(argc), argv, odin_app_Init, odin_app_Iterate, odin_app_Event, odin_app_Quit))
}
