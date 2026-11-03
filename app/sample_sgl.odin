package app

import math "core:math"
import sg "libs:sg"
import sgl "libs:sgl"

sgl_state :: struct {
    pass_action: sg.Pass_Action,
    tex_view:    sg.View,
    smp:         sg.Sampler,
    pip_3d:      sgl.Pipeline,
}
sgl_s: sgl_state

sgl_checkerboard_pixels := [8][8]u32{}

sgl_cube_body :: proc() {
    sgl.begin_quads()
    sgl.c3f(1.0, 0.0, 0.0)
    sgl.v3f_t2f(-1.0, 1.0, -1.0, -1.0, 1.0)
    sgl.v3f_t2f(1.0, 1.0, -1.0, 1.0, 1.0)
    sgl.v3f_t2f(1.0, -1.0, -1.0, 1.0, -1.0)
    sgl.v3f_t2f(-1.0, -1.0, -1.0, -1.0, -1.0)
    sgl.c3f(0.0, 1.0, 0.0)
    sgl.v3f_t2f(-1.0, -1.0, 1.0, -1.0, 1.0)
    sgl.v3f_t2f(1.0, -1.0, 1.0, 1.0, 1.0)
    sgl.v3f_t2f(1.0, 1.0, 1.0, 1.0, -1.0)
    sgl.v3f_t2f(-1.0, 1.0, 1.0, -1.0, -1.0)
    sgl.c3f(0.0, 0.0, 1.0)
    sgl.v3f_t2f(-1.0, -1.0, 1.0, -1.0, 1.0)
    sgl.v3f_t2f(-1.0, 1.0, 1.0, 1.0, 1.0)
    sgl.v3f_t2f(-1.0, 1.0, -1.0, 1.0, -1.0)
    sgl.v3f_t2f(-1.0, -1.0, -1.0, -1.0, -1.0)
    sgl.c3f(1.0, 0.5, 0.0)
    sgl.v3f_t2f(1.0, -1.0, 1.0, -1.0, 1.0)
    sgl.v3f_t2f(1.0, -1.0, -1.0, 1.0, 1.0)
    sgl.v3f_t2f(1.0, 1.0, -1.0, 1.0, -1.0)
    sgl.v3f_t2f(1.0, 1.0, 1.0, -1.0, -1.0)
    sgl.c3f(0.0, 0.5, 1.0)
    sgl.v3f_t2f(1.0, -1.0, -1.0, -1.0, 1.0)
    sgl.v3f_t2f(1.0, -1.0, 1.0, 1.0, 1.0)
    sgl.v3f_t2f(-1.0, -1.0, 1.0, 1.0, -1.0)
    sgl.v3f_t2f(-1.0, -1.0, -1.0, -1.0, -1.0)
    sgl.c3f(1.0, 0.0, 0.5)
    sgl.v3f_t2f(-1.0, 1.0, -1.0, -1.0, 1.0)
    sgl.v3f_t2f(-1.0, 1.0, 1.0, 1.0, 1.0)
    sgl.v3f_t2f(1.0, 1.0, 1.0, 1.0, -1.0)
    sgl.v3f_t2f(1.0, 1.0, -1.0, 1.0, -1.0)
    sgl.end()
}

sgl_draw_triangle_view :: proc() {
    sgl.defaults()
    sgl.begin_triangles()
    sgl.v2f_c3b(0.0, 0.5, 255, 0, 0)
    sgl.v2f_c3b(-0.5, -0.5, 0, 0, 255)
    sgl.v2f_c3b(0.5, -0.5, 0, 255, 0)
    sgl.end()
}

sgl_quad_angle: f32

sgl_draw_quad_view :: proc(t: f32) {
    sgl_quad_angle += 1.0 * t
    scale := 1.0 + math.sin(sgl.rad(sgl_quad_angle)) * 0.5
    sgl.defaults()
    sgl.rotate(sgl.rad(sgl_quad_angle), 0.0, 0.0, 1.0)
    sgl.scale(scale, scale, 1.0)
    sgl.begin_quads()
    sgl.v2f_c3b(-0.5, -0.5, 255, 255, 0)
    sgl.v2f_c3b(0.5, -0.5, 0, 255, 0)
    sgl.v2f_c3b(0.5, 0.5, 0, 0, 255)
    sgl.v2f_c3b(-0.5, 0.5, 255, 0, 0)
    sgl.end()
}

sgl_cubes_rot: [2]f32

sgl_draw_cubes :: proc(t: f32) {
    sgl_cubes_rot[0] += 1.0 * t
    sgl_cubes_rot[1] += 2.0 * t
    sgl.defaults()
    sgl.load_pipeline(sgl_s.pip_3d)
    sgl.matrix_mode_projection()
    sgl.perspective(sgl.rad(45.0), 1.0, 0.1, 100.0)
    sgl.matrix_mode_modelview()
    sgl.translate(0.0, 0.0, -12.0)
    sgl.rotate(sgl.rad(sgl_cubes_rot[0]), 1.0, 0.0, 0.0)
    sgl.rotate(sgl.rad(sgl_cubes_rot[1]), 0.0, 1.0, 0.0)
    sgl_cube_body()
    sgl.push_matrix()
    sgl.translate(0.0, 0.0, 3.0)
    sgl.scale(0.5, 0.5, 0.5)
    sgl.rotate(-2.0 * sgl.rad(sgl_cubes_rot[0]), 1.0, 0.0, 0.0)
    sgl.rotate(-2.0 * sgl.rad(sgl_cubes_rot[1]), 0.0, 1.0, 0.0)
    sgl_cube_body()
    sgl.push_matrix()
    sgl.translate(0.0, 0.0, 3.0)
    sgl.scale(0.5, 0.5, 0.5)
    sgl.rotate(-3.0 * sgl.rad(2 * sgl_cubes_rot[0]), 1.0, 0.0, 0.0)
    sgl.rotate(3.0 * sgl.rad(2 * sgl_cubes_rot[1]), 0.0, 0.0, 1.0)
    sgl_cube_body()
    sgl.pop_matrix()
    sgl.pop_matrix()
}

sgl_tex_frame_count: f32

sgl_draw_tex_cube :: proc(t: f32) {
    sgl_tex_frame_count += 1.0 * t
    a := sgl.rad(sgl_tex_frame_count)
    tex_rot := 0.5 * a
    tex_scale := 1.0 + math.sin(a) * 0.5
    eye_x := math.sin(a) * 6.0
    eye_z := math.cos(a) * 6.0
    eye_y := math.sin(a) * 3.0
    sgl.defaults()
    sgl.load_pipeline(sgl_s.pip_3d)
    sgl.enable_texture()
    sgl.texture(sgl_s.tex_view, sgl_s.smp)
    sgl.matrix_mode_projection()
    sgl.perspective(sgl.rad(45.0), 1.0, 0.1, 100.0)
    sgl.matrix_mode_modelview()
    sgl.lookat(eye_x, eye_y, eye_z, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
    sgl.matrix_mode_texture()
    sgl.rotate(tex_rot, 0.0, 0.0, 1.0)
    sgl.scale(tex_scale, tex_scale, 1.0)
    sgl_cube_body()
}

sgl_sample_init :: proc() {
    sgl.setup(&sgl.Desc{})
    for y in 0..<8 {
        for x in 0..<8 {
            sgl_checkerboard_pixels[y][x] = ((y ~ x) & 1) != 0 ? 0xFFFFFFFF : 0xFF000000
        }
    }
    sgl_s.tex_view = sg.make_view(&sg.View_Desc{
        texture = {
            image = sg.make_image(&sg.Image_Desc{
                width = 8, height = 8,
                data = sg.range_of(raw_data(&sgl_checkerboard_pixels), size_of(sgl_checkerboard_pixels)),
                label = "sgl-checkerboard",
            }),
        },
        label = "sgl-tex-view",
    })
    sgl_s.smp = sg.make_sampler(&sg.Sampler_Desc{
        min_filter = .NEAREST, mag_filter = .NEAREST,
        label = "sgl-sampler",
    })
    sgl_s.pip_3d = sgl.make_pipeline(&sg.Pipeline_Desc{
        cull_mode = .BACK,
        depth = {write_enabled = true, compare = .LESS_EQUAL},
        label = "sgl-pip-3d",
    })
    sgl_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}}}
}

sgl_sample_frame :: proc(w, h: i32) {
    t := frame_dt * 60.0
    dw, dh := w, h
    ww, hh := dh / 2, dh / 2
    x0 := dw / 2 - hh
    x1 := dw / 2
    y0: i32 = 0
    y1 := dh / 2
    sgl.viewport(x0, y0, ww, hh, true)
    sgl_draw_triangle_view()
    sgl.viewport(x1, y0, ww, hh, true)
    sgl_draw_quad_view(t)
    sgl.viewport(x0, y1, ww, hh, true)
    sgl_draw_cubes(t)
    sgl.viewport(x1, y1, ww, hh, true)
    sgl_draw_tex_cube(t)
    sgl.viewport(0, 0, dw, dh, true)
    sample_begin_pass(&sgl_s.pass_action, w, h)
    sgl.draw()
    sg.end_pass()
    sg.commit()
}

sgl_sample_shutdown :: proc() {
    sgl.destroy_pipeline(sgl_s.pip_3d)
    sg.destroy_view(sgl_s.tex_view)
    sg.destroy_sampler(sgl_s.smp)
    sgl.shutdown()
}
