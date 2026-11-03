package app

import sg "libs:sg"

// Sample registry and shared helpers.
Sample :: struct {
    name:    string,
    init:    proc(),
    frame:   proc(w, h: i32),
    shutdown: proc(),
}

samples_table := [12]Sample{
    {name = "triangle", init = triangle_init, frame = triangle_frame, shutdown = triangle_shutdown},
    {name = "quad", init = quad_init, frame = quad_frame, shutdown = quad_shutdown},
    {name = "mandelbrot", init = mandelbrot_init, frame = mandelbrot_frame, shutdown = mandelbrot_shutdown},
    {name = "cube", init = cube_init, frame = cube_frame, shutdown = cube_shutdown},
    {name = "instancing", init = instancing_init, frame = instancing_frame, shutdown = instancing_shutdown},
    {name = "offscreen", init = offscreen_init, frame = offscreen_frame, shutdown = offscreen_shutdown},
    {name = "dyntex", init = dyntex_init, frame = dyntex_frame, shutdown = dyntex_shutdown},
    {name = "mrt", init = mrt_init, frame = mrt_frame, shutdown = mrt_shutdown},
    {name = "blend", init = blend_init, frame = blend_frame, shutdown = blend_shutdown},
    {name = "shapes", init = shapes_init, frame = shapes_frame, shutdown = shapes_shutdown},
    {name = "sgl", init = sgl_sample_init, frame = sgl_sample_frame, shutdown = sgl_sample_shutdown},
    {name = "debugtext", init = debugtext_init, frame = debugtext_frame, shutdown = debugtext_shutdown},
}

sample_init :: proc(id: i32) {
    if id >= 0 && id < i32(len(samples_table)) {
        if samples_table[id].init != nil {
            samples_table[id].init()
        }
    }
}

sample_frame :: proc(id, w, h: i32) {
    if id >= 0 && id < i32(len(samples_table)) {
        if samples_table[id].frame != nil {
            samples_table[id].frame(w, h)
        }
    }
}

sample_shutdown :: proc(id: i32) {
    if id >= 0 && id < i32(len(samples_table)) {
        if samples_table[id].shutdown != nil {
            samples_table[id].shutdown()
        }
    }
}

// shared: begin the default pass with the sample's pass action
sample_begin_pass :: proc(pa: ^sg.Pass_Action, w, h: i32) {
    sg.begin_pass(&sg.Pass{action = pa^, swapchain = {width = w, height = h}})
}

// shared mvp used by cube/dyntex-style samples
sample_mvp :: proc(rx, ry, w, h, eye_dist: f32) -> Mat4 {
    proj := mat4_perspective(1.0471976, w / h, 0.01, 10.0)
    view := mat4_look_at({0, 1.5, eye_dist}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    model := mat4_mul(mat4_rotation_y(ry), mat4_rotation_x(rx))
    return mat4_mul(model, view_proj)
}
