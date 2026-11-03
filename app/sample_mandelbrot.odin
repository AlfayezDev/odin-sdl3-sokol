package app

import math "core:math"
import sg "libs:sg"
import shaders "libs:shaders"

mandelbrot_state :: struct {
    pip:  sg.Pipeline,
    time: f32,
}
mandelbrot_s: mandelbrot_state

mandelbrot_init :: proc() {
    mandelbrot_shd_desc := shaders.mandelbrot_mandelbrot_shader_desc(sg.query_backend())
    mandelbrot_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&mandelbrot_shd_desc),
        label = "mandelbrot-pipeline",
    })
}

mandelbrot_frame :: proc(w, h: i32) {
    mandelbrot_s.time = math.mod(mandelbrot_s.time + frame_dt, 20.0)
    aspect := f32(w) / f32(h)
    width := f32(4.0 * math.pow(0.6, f64(mandelbrot_s.time)))
    iter_max := 64 + i32(f32(math.log2(4.0 / f64(width))) * 32.0)
    if iter_max > 256 {
        iter_max = 256
    }
    fs_params := shaders.mandelbrot_Fs_Params{
        time = mandelbrot_s.time,
        width = width,
        aspect = {aspect >= 1.0 ? aspect : 1.0, aspect >= 1.0 ? 1.0 : 1.0 / aspect},
        iter_max = iter_max,
    }
    sg.begin_pass(&sg.Pass{
        action = {colors = {0 = {load_action = .DONTCARE}}},
        swapchain = {width = w, height = h},
    })
    sg.apply_pipeline(mandelbrot_s.pip)
    ur := sg.range_of(rawptr(&fs_params), size_of(fs_params))
	sg.apply_uniforms(shaders.mandelbrot_UB_fs_params, &ur)
    sg.draw(0, 3, 1)
    sg.end_pass()
    sg.commit()
}

mandelbrot_shutdown :: proc() {
    sg.destroy_pipeline(mandelbrot_s.pip)
}
