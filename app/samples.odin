package app

// The sokol-samples ports in Odin. Each sample owns its sokol-gfx resources
// and drives the whole frame (begin pass, draw, end pass, commit); timing
// comes from frame_dt (updated in main.odin).
import "core:math"
import sg "libs:sg"
import sgl "libs:sgl"
import sdtx "libs:sdtx"
import sshape "libs:sshape"
import shaders "libs:shaders"

// ---------------------------------------------------------------- triangle
triangle_state :: struct {
    pip:         sg.Pipeline,
    bind:        sg.Bindings,
    pass_action: sg.Pass_Action,
}
triangle_s: triangle_state

triangle_vertices_data := [18]f32{
    0.0, 0.5, 0.5, 1.0, 0.0, 0.0,
    -0.5, -0.5, 0.5, 0.0, 1.0, 0.0,
    0.5, -0.5, 0.5, 0.0, 0.0, 1.0,
}

triangle_init :: proc() {
    triangle_shd_desc := shaders.triangle_triangle_shader_desc(sg.query_backend())
    triangle_s.bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&triangle_vertices_data), size_of(triangle_vertices_data)),
        label = "triangle-vertices",
    })
    triangle_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&triangle_shd_desc),
        layout = {
            attrs = {
                shaders.triangle_ATTR_triangle_position = {format = .FLOAT3},
                shaders.triangle_ATTR_triangle_color0 = {format = .FLOAT3},
            },
        },
        label = "triangle-pipeline",
    })
    triangle_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.08, 0.22, 0.43, 1.0}}}}
}

triangle_frame :: proc(w, h: i32) {
    sample_begin_pass(&triangle_s.pass_action, w, h)
    sg.apply_pipeline(triangle_s.pip)
    sg.apply_bindings(&triangle_s.bind)
    sg.draw(0, 3, 1)
    sg.end_pass()
    sg.commit()
}

triangle_shutdown :: proc() {
    sg.destroy_pipeline(triangle_s.pip)
    sg.destroy_buffer(triangle_s.bind.vertex_buffers[0])
}

// ---------------------------------------------------------------- registry
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

// ---------------------------------------------------------------- quad
quad_state :: struct {
    pass_action: sg.Pass_Action,
    pip:         sg.Pipeline,
    bind:        sg.Bindings,
}
quad_s: quad_state

quad_init :: proc() {
    vertices := [28]f32{
        -0.5, 0.5, 0.5, 1.0, 0.0, 0.0, 1.0,
        0.5, 0.5, 0.5, 0.0, 1.0, 0.0, 1.0,
        0.5, -0.5, 0.5, 0.0, 0.0, 1.0, 1.0,
        -0.5, -0.5, 0.5, 1.0, 1.0, 0.0, 1.0,
    }
    quad_s.bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&vertices), size_of(vertices)),
        label = "quad-vertices",
    })
    indices := [6]u16{0, 1, 2, 0, 2, 3}
    quad_s.bind.index_buffer = sg.make_buffer(&sg.Buffer_Desc{
        usage = {index_buffer = true},
        data = sg.range_of(raw_data(&indices), size_of(indices)),
        label = "quad-indices",
    })
    quad_shd_desc := shaders.quad_quad_shader_desc(sg.query_backend())
    quad_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&quad_shd_desc),
        index_type = .UINT16,
        layout = {
            attrs = {
                shaders.quad_ATTR_quad_position = {format = .FLOAT3},
                shaders.quad_ATTR_quad_color0 = {format = .FLOAT4},
            },
        },
        label = "quad-pipeline",
    })
    quad_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}}}
}

quad_frame :: proc(w, h: i32) {
    sample_begin_pass(&quad_s.pass_action, w, h)
    sg.apply_pipeline(quad_s.pip)
    sg.apply_bindings(&quad_s.bind)
    sg.draw(0, 6, 1)
    sg.end_pass()
    sg.commit()
}

quad_shutdown :: proc() {
    sg.destroy_pipeline(quad_s.pip)
    sg.destroy_buffer(quad_s.bind.vertex_buffers[0])
    sg.destroy_buffer(quad_s.bind.index_buffer)
}

// ---------------------------------------------------------------- mandelbrot
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

// shared mvp used by cube/dyntex-style samples
sample_mvp :: proc(rx, ry, w, h, eye_dist: f32) -> Mat4 {
    proj := mat4_perspective(1.0471976, w / h, 0.01, 10.0)
    view := mat4_look_at({0, 1.5, eye_dist}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    model := mat4_mul(mat4_rotation_y(ry), mat4_rotation_x(rx))
    return mat4_mul(model, view_proj)
}

// ---------------------------------------------------------------- cube
cube_state :: struct {
    rx, ry: f32,
    pip:    sg.Pipeline,
    bind:   sg.Bindings,
}
cube_s: cube_state

cube_vertices_data := [24 * 7]f32{
    -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
    1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
    1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
    -1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
    -1.0, -1.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    1.0, -1.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    -1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
    -1.0, 1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
    -1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0,
    -1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0,
    1.0, -1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
    1.0, 1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
    1.0, 1.0, 1.0, 1.0, 0.5, 0.0, 1.0,
    1.0, -1.0, 1.0, 1.0, 0.5, 0.0, 1.0,
    -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
    -1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 1.0,
    1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 1.0,
    1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
    -1.0, 1.0, -1.0, 1.0, 0.0, 0.5, 1.0,
    -1.0, 1.0, 1.0, 1.0, 0.0, 0.5, 1.0,
    1.0, 1.0, 1.0, 1.0, 0.0, 0.5, 1.0,
    1.0, 1.0, -1.0, 1.0, 0.0, 0.5, 1.0,
}
cube_indices_data := [36]u16{
    0, 1, 2, 0, 2, 3,
    6, 5, 4, 7, 6, 4,
    8, 9, 10, 8, 10, 11,
    14, 13, 12, 15, 14, 12,
    16, 17, 18, 16, 18, 19,
    22, 21, 20, 23, 22, 20,
}

cube_init :: proc() {
    vbuf := sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&cube_vertices_data), size_of(cube_vertices_data)),
        label = "cube-vertices",
    })
    ibuf := sg.make_buffer(&sg.Buffer_Desc{
        usage = {index_buffer = true},
        data = sg.range_of(raw_data(&cube_indices_data), size_of(cube_indices_data)),
        label = "cube-indices",
    })
    cube_shd_desc := shaders.cube_cube_shader_desc(sg.query_backend())
    cube_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            buffers = {0 = {stride = 28}},
            attrs = {
                shaders.cube_ATTR_cube_position = {format = .FLOAT3},
                shaders.cube_ATTR_cube_color0 = {format = .FLOAT4},
            },
        },
        shader = sg.make_shader(&cube_shd_desc),
        index_type = .UINT16,
        cull_mode = .BACK,
        depth = {write_enabled = true, compare = .LESS_EQUAL},
        label = "cube-pipeline",
    })
    cube_s.bind = {vertex_buffers = {0 = vbuf}, index_buffer = ibuf}
}

cube_frame :: proc(w, h: i32) {
    t := frame_dt * 60.0
    cube_s.rx += 1.0 * t
    cube_s.ry += 2.0 * t
    vs_params := shaders.cube_Vs_Params{mvp = sample_mvp(cube_s.rx, cube_s.ry, f32(w), f32(h), 4.0)}
    pa := sg.Pass_Action{colors = {0 = {load_action = .CLEAR, clear_value = {0.25, 0.5, 0.75, 1.0}}}}
    sample_begin_pass(&pa, w, h)
    sg.apply_pipeline(cube_s.pip)
    sg.apply_bindings(&cube_s.bind)
    ur2 := sg.range_of(rawptr(&vs_params), size_of(vs_params))
	sg.apply_uniforms(shaders.cube_UB_vs_params, &ur2)
    sg.draw(0, 36, 1)
    sg.end_pass()
    sg.commit()
}

cube_shutdown :: proc() {
    sg.destroy_pipeline(cube_s.pip)
    sg.destroy_buffer(cube_s.bind.vertex_buffers[0])
    sg.destroy_buffer(cube_s.bind.index_buffer)
}

// ---------------------------------------------------------------- instancing
INST_MAX_PARTICLES :: 512 * 1024
INST_EMIT_PER_FRAME :: 10

instancing_state :: struct {
    pass_action: sg.Pass_Action,
    pip:         sg.Pipeline,
    bind:        sg.Bindings,
    ry:          f32,
    cur_num_particles: i32,
    pos:         [INST_MAX_PARTICLES][3]f32,
    vel:         [INST_MAX_PARTICLES][3]f32,
}
inst_s: instancing_state

inst_rand: u32 = 0x12345678

inst_xorshift32 :: proc() -> u32 {
    inst_rand = inst_rand ~ (inst_rand << 13)
    inst_rand = inst_rand ~ (inst_rand >> 17)
    inst_rand = inst_rand ~ (inst_rand << 5)
    return inst_rand
}

instancing_init :: proc() {
    inst_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}}}
    r: f32 = 0.05
    vertices := [42]f32{
        0.0, -r, 0.0, 1.0, 0.0, 0.0, 1.0,
        r, 0.0, r, 0.0, 1.0, 0.0, 1.0,
        r, 0.0, -r, 0.0, 0.0, 1.0, 1.0,
        -r, 0.0, -r, 1.0, 1.0, 0.0, 1.0,
        -r, 0.0, r, 0.0, 1.0, 1.0, 1.0,
        0.0, r, 0.0, 1.0, 0.0, 1.0, 1.0,
    }
    inst_s.bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&vertices), size_of(vertices)),
        label = "geometry-vertices",
    })
    indices := [24]u16{
        0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1,
        5, 1, 2, 5, 2, 3, 5, 3, 4, 5, 4, 1,
    }
    inst_s.bind.index_buffer = sg.make_buffer(&sg.Buffer_Desc{
        usage = {index_buffer = true},
        data = sg.range_of(raw_data(&indices), size_of(indices)),
        label = "geometry-indices",
    })
    inst_s.bind.vertex_buffers[1] = sg.make_buffer(&sg.Buffer_Desc{
        size = size_of(inst_s.pos),
        usage = {write_transient = true},
        label = "instance-data",
    })
    inst_shd_desc := shaders.instancing_instancing_shader_desc(sg.query_backend())
    inst_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            buffers = {1 = {step_func = .PER_INSTANCE}},
            attrs = {
                shaders.instancing_ATTR_instancing_pos = {format = .FLOAT3, buffer_index = 0},
                shaders.instancing_ATTR_instancing_color0 = {format = .FLOAT4, buffer_index = 0},
                shaders.instancing_ATTR_instancing_inst_pos = {format = .FLOAT3, buffer_index = 1},
            },
        },
        shader = sg.make_shader(&inst_shd_desc),
        index_type = .UINT16,
        cull_mode = .BACK,
        depth = {compare = .LESS_EQUAL, write_enabled = true},
        label = "instancing-pipeline",
    })
}

instancing_frame :: proc(w, h: i32) {
    frame_time_s := frame_dt
    for i in 0..<INST_EMIT_PER_FRAME {
        if inst_s.cur_num_particles < INST_MAX_PARTICLES {
            inst_s.pos[inst_s.cur_num_particles] = {0, 0, 0}
            inst_s.vel[inst_s.cur_num_particles] = {
                (f32(inst_xorshift32() & 0x7FFF) / 0x7FFF) - 0.5,
                (f32(inst_xorshift32() & 0x7FFF) / 0x7FFF) * 0.5 + 2.0,
                (f32(inst_xorshift32() & 0x7FFF) / 0x7FFF) - 0.5,
            }
            inst_s.cur_num_particles += 1
        } else {
            break
        }
    }
    for i in 0..<inst_s.cur_num_particles {
        inst_s.vel[i][1] -= 1.0 * frame_time_s
        inst_s.pos[i][0] += inst_s.vel[i][0] * frame_time_s
        inst_s.pos[i][1] += inst_s.vel[i][1] * frame_time_s
        inst_s.pos[i][2] += inst_s.vel[i][2] * frame_time_s
        if inst_s.pos[i][1] < -2.0 {
            inst_s.pos[i][1] = -1.8
            inst_s.vel[i][1] = -inst_s.vel[i][1]
            inst_s.vel[i][0] *= 0.8
            inst_s.vel[i][1] *= 0.8
            inst_s.vel[i][2] *= 0.8
        }
    }
    sg.write_buffer_transient(&sg.Write_Buffer_Desc{
        src = {data = sg.range_of(raw_data(&inst_s.pos), size_of([3]f32) * uint(inst_s.cur_num_particles))},
        dst = {buffer = inst_s.bind.vertex_buffers[1]},
        size = size_of([3]f32) * uint(inst_s.cur_num_particles),
    })
    proj := mat4_perspective(1.0471976, f32(w) / f32(h), 0.01, 50.0)
    view := mat4_look_at({0, 1.5, 8.0}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    inst_s.ry += 60.0 * frame_time_s
    vs_params := shaders.instancing_Vs_Params{mvp = mat4_mul(mat4_rotation_y(inst_s.ry), view_proj)}
    sample_begin_pass(&inst_s.pass_action, w, h)
    sg.apply_pipeline(inst_s.pip)
    sg.apply_bindings(&inst_s.bind)
    ur3 := sg.range_of(rawptr(&vs_params), size_of(vs_params))
	sg.apply_uniforms(shaders.instancing_UB_vs_params, &ur3)
    sg.draw(0, 24, inst_s.cur_num_particles)
    sg.end_pass()
    sg.commit()
}

instancing_shutdown :: proc() {
    sg.destroy_pipeline(inst_s.pip)
    sg.destroy_buffer(inst_s.bind.vertex_buffers[0])
    sg.destroy_buffer(inst_s.bind.index_buffer)
    sg.destroy_buffer(inst_s.bind.vertex_buffers[1])
}

// ---------------------------------------------------------------- offscreen
offscreen_state :: struct {
    offscreen_pass: sg.Pass,
    offscreen_pip:  sg.Pipeline,
    offscreen_bind: sg.Bindings,
    display_pass_action: sg.Pass_Action,
    display_pip:    sg.Pipeline,
    display_bind:   sg.Bindings,
    donut:  sshape.Element_Range,
    sphere: sshape.Element_Range,
    rx, ry: f32,
    color_img:  sg.Image,
    depth_img:  sg.Image,
    smp:        sg.Sampler,
}
off_s: offscreen_state

offscreen_vertices_buf: [24 * 4000]u8
offscreen_indices_buf: [24000]u16

offscreen_mvp :: proc(rx, ry, aspect, eye_dist: f32) -> Mat4 {
    proj := mat4_perspective(0.7853982, aspect, 0.01, 10.0)
    view := mat4_look_at({0, 0, eye_dist}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    model := mat4_mul(mat4_rotation_x(rx), mat4_rotation_y(ry))
    return mat4_mul(model, view_proj)
}

offscreen_init :: proc() {
    off_s.display_pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.25, 0.45, 0.65, 1.0}}}}
    color_img := sg.make_image(&sg.Image_Desc{
        usage = {color_attachment = true},
        width = 256, height = 256,
        pixel_format = .RGBA8,
        sample_count = 1,
        label = "color-image",
    })
    depth_img := sg.make_image(&sg.Image_Desc{
        usage = {depth_stencil_attachment = true},
        width = 256, height = 256,
        pixel_format = .DEPTH,
        sample_count = 1,
        label = "depth-image",
    })
    off_s.offscreen_pass = sg.Pass{
        attachments = {
            colors = {0 = sg.make_view(&sg.View_Desc{color_attachment = {image = color_img}, label = "color-attachment"})},
            depth_stencil = sg.make_view(&sg.View_Desc{depth_stencil_attachment = {image = depth_img}, label = "depth-attachment"}),
        },
        action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.25, 0.25, 0.25, 1.0}}}},
        label = "offscreen-pass",
    }
    shp := sshape.State{
        disable = {colors = true},
        vertices = {buffer = sshape.range_of(raw_data(&offscreen_vertices_buf), size_of(offscreen_vertices_buf))},
        indices = {buffer = sshape.range_of(raw_data(&offscreen_indices_buf), size_of(offscreen_indices_buf))},
    }
    sshape.build_torus(&shp, &sshape.Torus{radius = 0.5, ring_radius = 0.3, sides = 20, rings = 36})
    off_s.donut = sshape.element_range(&shp)
    sshape.build_sphere(&shp, &sshape.Sphere{radius = 0.5, slices = 72, stacks = 40})
    off_s.sphere = sshape.element_range(&shp)
    vbuf_desc := sshape.vertex_buffer_desc(&shp)
    ibuf_desc := sshape.index_buffer_desc(&shp)
    vbuf_desc.label = "shape-vbuf"
    ibuf_desc.label = "shape-ibuf"
    vbuf := sg.make_buffer(&vbuf_desc)
    ibuf := sg.make_buffer(&ibuf_desc)
    off_shd_desc := shaders.offscreen_offscreen_shader_desc(sg.query_backend())
    off_s.offscreen_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            buffers = {0 = sshape.vertex_buffer_layout_state(&shp)},
            attrs = {
                shaders.offscreen_ATTR_offscreen_position = sshape.position_vertex_attr_state(&shp),
                shaders.offscreen_ATTR_offscreen_normal = sshape.normal_vertex_attr_state(&shp),
            },
        },
        shader = sg.make_shader(&off_shd_desc),
        index_type = .UINT16,
        cull_mode = .BACK,
        sample_count = 1,
        depth = {pixel_format = .DEPTH, compare = .LESS_EQUAL, write_enabled = true},
        colors = {0 = {pixel_format = .RGBA8}},
        label = "offscreen-pipeline",
    })
    disp_shd_desc := shaders.offscreen_default_shader_desc(sg.query_backend())
    off_s.display_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            buffers = {0 = sshape.vertex_buffer_layout_state(&shp)},
            attrs = {
                shaders.offscreen_ATTR_default_position = sshape.position_vertex_attr_state(&shp),
                shaders.offscreen_ATTR_default_normal = sshape.normal_vertex_attr_state(&shp),
                shaders.offscreen_ATTR_default_texcoord0 = sshape.texcoord_vertex_attr_state(&shp),
            },
        },
        shader = sg.make_shader(&disp_shd_desc),
        index_type = .UINT16,
        cull_mode = .BACK,
        depth = {compare = .LESS_EQUAL, write_enabled = true},
        label = "default-pipeline",
    })
    smp := sg.make_sampler(&sg.Sampler_Desc{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        wrap_u = .REPEAT,
        wrap_v = .REPEAT,
        label = "sampler",
    })
    off_s.offscreen_bind = {vertex_buffers = {0 = vbuf}, index_buffer = ibuf}
    off_s.display_bind = {
        vertex_buffers = {0 = vbuf},
        index_buffer = ibuf,
        views = {shaders.offscreen_VIEW_tex = sg.make_view(&sg.View_Desc{texture = {image = color_img}, label = "texture-view"})},
        samplers = {shaders.offscreen_SMP_smp = smp},
    }
    off_s.color_img = color_img
    off_s.depth_img = depth_img
    off_s.smp = smp
}

offscreen_frame :: proc(w, h: i32) {
    t := frame_dt * 60.0
    off_s.rx += 1.0 * t
    off_s.ry += 2.0 * t
    vs_params := shaders.offscreen_Vs_Params{mvp = offscreen_mvp(off_s.rx, off_s.ry, 1.0, 2.5)}
    sg.begin_pass(&off_s.offscreen_pass)
    sg.apply_pipeline(off_s.offscreen_pip)
    sg.apply_bindings(&off_s.offscreen_bind)
    ur4 := sg.range_of(rawptr(&vs_params), size_of(vs_params))
	sg.apply_uniforms(shaders.offscreen_UB_vs_params, &ur4)
    sg.draw(off_s.donut.base_element, off_s.donut.num_elements, 1)
    sg.end_pass()
    vs_params = shaders.offscreen_Vs_Params{mvp = offscreen_mvp(-off_s.rx * 0.25, off_s.ry * 0.25, f32(w) / f32(h), 1.5)}
    sample_begin_pass(&off_s.display_pass_action, w, h)
    sg.apply_pipeline(off_s.display_pip)
    sg.apply_bindings(&off_s.display_bind)
    ur5 := sg.range_of(rawptr(&vs_params), size_of(vs_params))
	sg.apply_uniforms(shaders.offscreen_UB_vs_params, &ur5)
    sg.draw(off_s.sphere.base_element, off_s.sphere.num_elements, 1)
    sg.end_pass()
    sg.commit()
}

offscreen_shutdown :: proc() {
    sg.destroy_pipeline(off_s.offscreen_pip)
    sg.destroy_pipeline(off_s.display_pip)
    sg.destroy_buffer(off_s.offscreen_bind.vertex_buffers[0])
    sg.destroy_buffer(off_s.offscreen_bind.index_buffer)
    sg.destroy_view(off_s.offscreen_pass.attachments.colors[0])
    sg.destroy_view(off_s.offscreen_pass.attachments.depth_stencil)
    sg.destroy_view(off_s.display_bind.views[shaders.offscreen_VIEW_tex])
    sg.destroy_image(off_s.color_img)
    sg.destroy_image(off_s.depth_img)
}

// ---------------------------------------------------------------- dyntex
DYNT_IMAGE_W :: 128
DYNT_IMAGE_H :: 128
DYNT_LIVING :: u32(0xFFFFFFFF)
DYNT_DEAD :: u32(0xFF000000)

dyntex_state :: struct {
    pass_action: sg.Pass_Action,
    pip:         sg.Pipeline,
    img:         sg.Image,
    bind:        sg.Bindings,
    rx, ry:      f32,
    update_count: i32,
    pixels:      [DYNT_IMAGE_W][DYNT_IMAGE_H]u32,
}
dynt_s: dyntex_state

dyntex_vertices_data := [24 * 9]f32{
    -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0,
    1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0,
    1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0,
    -1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0,
    -1.0, -1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0,
    1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0,
    -1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, -1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0,
    -1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0,
    -1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0,
    1.0, -1.0, -1.0, 1.0, 0.5, 0.0, 1.0, 0.0, 0.0,
    1.0, 1.0, -1.0, 1.0, 0.5, 0.0, 1.0, 1.0, 0.0,
    1.0, 1.0, 1.0, 1.0, 0.5, 0.0, 1.0, 1.0, 1.0,
    1.0, -1.0, 1.0, 1.0, 0.5, 0.0, 1.0, 0.0, 1.0,
    -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0, 0.0, 0.0,
    -1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 1.0, 1.0, 0.0,
    1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0,
    1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0, 0.0, 1.0,
    -1.0, 1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 0.0, 0.0,
    -1.0, 1.0, 1.0, 1.0, 0.0, 0.5, 1.0, 1.0, 0.0,
    1.0, 1.0, 1.0, 1.0, 0.0, 0.5, 1.0, 1.0, 1.0,
    1.0, 1.0, -1.0, 1.0, 0.0, 0.5, 1.0, 0.0, 1.0,
}

gol_init :: proc() {
    for y in 0..<DYNT_IMAGE_H {
        for x in 0..<DYNT_IMAGE_W {
            dynt_s.pixels[y][x] = (inst_xorshift32() & 255) > 230 ? DYNT_LIVING : DYNT_DEAD
        }
    }
}

gol_update :: proc() {
    for y in 0..<DYNT_IMAGE_H {
        for x in 0..<DYNT_IMAGE_W {
            num_living_neighbours := 0
            for ny in -1..<2 {
                for nx in -1..<2 {
                    if nx == 0 && ny == 0 {
                        continue
                    }
                    if dynt_s.pixels[(y + ny) & (DYNT_IMAGE_H - 1)][(x + nx) & (DYNT_IMAGE_W - 1)] == DYNT_LIVING {
                        num_living_neighbours += 1
                    }
                }
            }
            if dynt_s.pixels[y][x] == DYNT_LIVING {
                if num_living_neighbours < 2 || num_living_neighbours > 3 {
                    dynt_s.pixels[y][x] = DYNT_DEAD
                }
            } else if num_living_neighbours == 3 {
                dynt_s.pixels[y][x] = DYNT_LIVING
            }
        }
    }
    dynt_s.update_count += 1
    if dynt_s.update_count > 240 {
        gol_init()
        dynt_s.update_count = 0
    }
}

dyntex_init :: proc() {
    dynt_s.img = sg.make_image(&sg.Image_Desc{
        usage = {write_transient = true},
        width = DYNT_IMAGE_W, height = DYNT_IMAGE_H,
        pixel_format = .RGBA8,
        label = "dynamic-texture",
    })
    tex_view := sg.make_view(&sg.View_Desc{texture = {image = dynt_s.img}, label = "dynamic-texture-view"})
    smp := sg.make_sampler(&sg.Sampler_Desc{
        min_filter = .LINEAR, mag_filter = .LINEAR,
        wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE,
        label = "sampler",
    })
    vbuf := sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&dyntex_vertices_data), size_of(dyntex_vertices_data)),
        label = "cube-vertices",
    })
    ibuf := sg.make_buffer(&sg.Buffer_Desc{
        usage = {index_buffer = true},
        data = sg.range_of(raw_data(&cube_indices_data), size_of(cube_indices_data)),
        label = "cube-indices",
    })
    dynt_shd_desc := shaders.dyntex_dyntex_shader_desc(sg.query_backend())
    dynt_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            attrs = {
                shaders.dyntex_ATTR_dyntex_position = {format = .FLOAT3},
                shaders.dyntex_ATTR_dyntex_color0 = {format = .FLOAT4},
                shaders.dyntex_ATTR_dyntex_texcoord0 = {format = .FLOAT2},
            },
        },
        shader = sg.make_shader(&dynt_shd_desc),
        index_type = .UINT16,
        cull_mode = .BACK,
        depth = {compare = .LESS_EQUAL, write_enabled = true},
        label = "dyntex-cube-pipeline",
    })
    dynt_s.bind = {
        vertex_buffers = {0 = vbuf},
        index_buffer = ibuf,
        views = {shaders.dyntex_VIEW_tex = tex_view},
        samplers = {shaders.dyntex_SMP_smp = smp},
    }
    dynt_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}}}
    gol_init()
}

dyntex_frame :: proc(w, h: i32) {
    t := frame_dt * 60.0
    dynt_s.rx += 1.0 * t
    dynt_s.ry += 2.0 * t
    vs_params := shaders.dyntex_Vs_Params{mvp = sample_mvp(dynt_s.rx, dynt_s.ry, f32(w), f32(h), 4.0)}
    gol_update()
    sg.write_image_transient(&sg.Write_Image_Desc{
        src = {data = sg.range_of(raw_data(&dynt_s.pixels), size_of(dynt_s.pixels))},
        dst = {image = dynt_s.img},
    })
    sample_begin_pass(&dynt_s.pass_action, w, h)
    sg.apply_pipeline(dynt_s.pip)
    sg.apply_bindings(&dynt_s.bind)
    ur6 := sg.range_of(rawptr(&vs_params), size_of(vs_params))
	sg.apply_uniforms(shaders.dyntex_UB_vs_params, &ur6)
    sg.draw(0, 36, 1)
    sg.end_pass()
    sg.commit()
}

dyntex_shutdown :: proc() {
    sg.destroy_pipeline(dynt_s.pip)
    sg.destroy_buffer(dynt_s.bind.vertex_buffers[0])
    sg.destroy_buffer(dynt_s.bind.index_buffer)
    sg.destroy_view(dynt_s.bind.views[shaders.dyntex_VIEW_tex])
    sg.destroy_sampler(dynt_s.bind.samplers[shaders.dyntex_SMP_smp])
    sg.destroy_image(dynt_s.img)
}

// ---------------------------------------------------------------- mrt
MRT_NUM :: 3

mrt_vertex :: struct {
    x, y, z, b: f32,
}

mrt_state :: struct {
    offscreen_pip:  sg.Pipeline,
    offscreen_bind: sg.Bindings,
    offscreen_pass: sg.Pass,
    display_pass_action: sg.Pass_Action,
    display_pip:    sg.Pipeline,
    display_bind:   sg.Bindings,
    dbg_pip:        sg.Pipeline,
    dbg_bind:       sg.Bindings,
    color_images:   [MRT_NUM]sg.Image,
    depth_image:    sg.Image,
    rx, ry:         f32,
    cur_w, cur_h:   i32,
    attachments_ready: b32,
}
mrt_s: mrt_state

mrt_cube_vertices := [24]mrt_vertex{
    {-1, -1, -1, 1.0}, {1, -1, -1, 1.0}, {1, 1, -1, 1.0}, {-1, 1, -1, 1.0},
    {-1, -1, 1, 0.8}, {1, -1, 1, 0.8}, {1, 1, 1, 0.8}, {-1, 1, 1, 0.8},
    {-1, -1, -1, 0.6}, {-1, 1, -1, 0.6}, {-1, 1, 1, 0.6}, {-1, -1, 1, 0.6},
    {1, -1, -1, 0.4}, {1, 1, -1, 0.4}, {1, 1, 1, 0.4}, {1, -1, 1, 0.4},
    {-1, -1, -1, 0.5}, {-1, -1, 1, 0.5}, {1, -1, 1, 0.5}, {1, -1, -1, 0.5},
    {-1, 1, -1, 0.7}, {-1, 1, 1, 0.7}, {1, 1, 1, 0.7}, {1, 1, -1, 0.7},
}

mrt_reinit_attachments :: proc(width, height: i32) {
    if mrt_s.attachments_ready != false {
        for i in 0..<MRT_NUM {
            sg.uninit_image(mrt_s.color_images[i])
            sg.uninit_view(mrt_s.offscreen_pass.attachments.colors[i])
            sg.uninit_view(mrt_s.display_bind.views[shaders.mrt_VIEW_tex0 + i])
        }
        sg.uninit_image(mrt_s.depth_image)
        sg.uninit_view(mrt_s.offscreen_pass.attachments.depth_stencil)
    }
    for i in 0..<MRT_NUM {
        sg.init_image(mrt_s.color_images[i], &sg.Image_Desc{
            usage = {color_attachment = true},
            width = width, height = height,
            sample_count = 1,
        })
        sg.init_view(mrt_s.offscreen_pass.attachments.colors[i], &sg.View_Desc{
            color_attachment = {image = mrt_s.color_images[i]},
        })
        sg.init_view(mrt_s.display_bind.views[shaders.mrt_VIEW_tex0 + i], &sg.View_Desc{
            texture = {image = mrt_s.color_images[i]},
        })
    }
    sg.init_image(mrt_s.depth_image, &sg.Image_Desc{
        usage = {depth_stencil_attachment = true},
        width = width, height = height,
        pixel_format = .DEPTH,
        sample_count = 1,
    })
    sg.init_view(mrt_s.offscreen_pass.attachments.depth_stencil, &sg.View_Desc{
        depth_stencil_attachment = {image = mrt_s.depth_image},
    })
    mrt_s.cur_w = width
    mrt_s.cur_h = height
    mrt_s.attachments_ready = true
}

mrt_init :: proc() {
    mrt_s.display_pass_action = {
        colors = {0 = {load_action = .DONTCARE}},
        depth = {load_action = .DONTCARE},
        stencil = {load_action = .DONTCARE},
    }
    for i in 0..<MRT_NUM {
        mrt_s.color_images[i] = sg.alloc_image()
        mrt_s.offscreen_pass.attachments.colors[i] = sg.alloc_view()
        mrt_s.display_bind.views[shaders.mrt_VIEW_tex0 + i] = sg.alloc_view()
    }
    mrt_s.depth_image = sg.alloc_image()
    mrt_s.offscreen_pass.attachments.depth_stencil = sg.alloc_view()

    mrt_s.offscreen_bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&mrt_cube_vertices), size_of(mrt_cube_vertices)),
        label = "cube vertices",
    })
    mrt_s.offscreen_bind.index_buffer = sg.make_buffer(&sg.Buffer_Desc{
        usage = {index_buffer = true},
        data = sg.range_of(raw_data(&cube_indices_data), size_of(cube_indices_data)),
        label = "cube indices",
    })
    mrt_off_shd_desc := shaders.mrt_offscreen_shader_desc(sg.query_backend())
    mrt_s.offscreen_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&mrt_off_shd_desc),
        layout = {
            buffers = {0 = {stride = size_of(mrt_vertex)}},
            attrs = {
                shaders.mrt_ATTR_offscreen_pos = {offset = i32(offset_of(mrt_vertex, x)), format = .FLOAT3},
                shaders.mrt_ATTR_offscreen_bright0 = {offset = i32(offset_of(mrt_vertex, b)), format = .FLOAT},
            },
        },
        index_type = .UINT16,
        cull_mode = .BACK,
        sample_count = 1,
        depth = {pixel_format = .DEPTH, compare = .LESS_EQUAL, write_enabled = true},
        color_count = MRT_NUM,
        label = "mrt offscreen pipeline",
    })
    mrt_s.offscreen_pass.action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {0.25, 0, 0, 1}},
            1 = {load_action = .CLEAR, clear_value = {0, 0.25, 0, 1}},
            2 = {load_action = .CLEAR, clear_value = {0, 0, 0.25, 1}},
        },
    }
    quad_vertices := [8]f32{0, 0, 1, 0, 0, 1, 1, 1}
    quad_vbuf := sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&quad_vertices), size_of(quad_vertices)),
        label = "quad vertices",
    })
    mrt_fsq_shd_desc := shaders.mrt_fsq_shader_desc(sg.query_backend())
    mrt_s.display_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&mrt_fsq_shd_desc),
        layout = {attrs = {shaders.mrt_ATTR_fsq_pos = {format = .FLOAT2}}},
        primitive_type = .TRIANGLE_STRIP,
        label = "fsq pipeline",
    })
    smp := sg.make_sampler(&sg.Sampler_Desc{
        min_filter = .LINEAR, mag_filter = .LINEAR,
        wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE,
        label = "mrt sampler",
    })
    mrt_s.display_bind.vertex_buffers[0] = quad_vbuf
    mrt_s.display_bind.samplers[shaders.mrt_SMP_smp] = smp
    mrt_dbg_shd_desc := shaders.mrt_dbg_shader_desc(sg.query_backend())
    mrt_s.dbg_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&mrt_dbg_shd_desc),
        layout = {attrs = {shaders.mrt_ATTR_dbg_pos = {format = .FLOAT2}}},
        primitive_type = .TRIANGLE_STRIP,
        label = "dbg pipeline",
    })
    mrt_s.dbg_bind = {
        vertex_buffers = {0 = quad_vbuf},
        samplers = {shaders.mrt_SMP_smp = smp},
    }
}

mrt_frame :: proc(w, h: i32) {
    if w != mrt_s.cur_w || h != mrt_s.cur_h {
        mrt_reinit_attachments(w, h)
    }
    t := frame_dt * 60.0
    proj := mat4_perspective(0.7853982, f32(w) / f32(h), 0.01, 10.0)
    view := mat4_look_at({0, 1.5, 4.0}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    mrt_s.rx += 1.0 * t
    mrt_s.ry += 2.0 * t
    model := mat4_mul(mat4_rotation_y(mrt_s.ry), mat4_rotation_x(mrt_s.rx))
    offscreen_params := shaders.mrt_Offscreen_Params{mvp = mat4_mul(model, view_proj)}
    fsq_params := shaders.mrt_Fsq_Params{
        offset = {math.sin(mrt_s.rx * 0.01) * 0.1, math.sin(mrt_s.ry * 0.01) * 0.1},
    }
    sg.begin_pass(&mrt_s.offscreen_pass)
    sg.apply_pipeline(mrt_s.offscreen_pip)
    sg.apply_bindings(&mrt_s.offscreen_bind)
    ur7 := sg.range_of(rawptr(&offscreen_params), size_of(offscreen_params))
	sg.apply_uniforms(shaders.mrt_UB_offscreen_params, &ur7)
    sg.draw(0, 36, 1)
    sg.end_pass()

    sample_begin_pass(&mrt_s.display_pass_action, w, h)
    sg.apply_pipeline(mrt_s.display_pip)
    sg.apply_bindings(&mrt_s.display_bind)
    ur8 := sg.range_of(rawptr(&fsq_params), size_of(fsq_params))
	sg.apply_uniforms(shaders.mrt_UB_fsq_params, &ur8)
    sg.draw(0, 4, 1)
    sg.apply_pipeline(mrt_s.dbg_pip)
    for i in 0..<MRT_NUM {
        sg.apply_viewport(i32(i) * 100, 0, 100, 100, false)
        mrt_s.dbg_bind.views[shaders.mrt_VIEW_tex] = mrt_s.display_bind.views[shaders.mrt_VIEW_tex0 + i]
        sg.apply_bindings(&mrt_s.dbg_bind)
        sg.draw(0, 4, 1)
    }
    sg.apply_viewport(0, 0, w, h, false)
    sg.end_pass()
    sg.commit()
}

mrt_shutdown :: proc() {
    sg.destroy_pipeline(mrt_s.offscreen_pip)
    sg.destroy_pipeline(mrt_s.display_pip)
    sg.destroy_pipeline(mrt_s.dbg_pip)
    sg.destroy_buffer(mrt_s.offscreen_bind.vertex_buffers[0])
    sg.destroy_buffer(mrt_s.offscreen_bind.index_buffer)
    sg.destroy_buffer(mrt_s.display_bind.vertex_buffers[0])
    sg.destroy_sampler(mrt_s.display_bind.samplers[shaders.mrt_SMP_smp])
    if mrt_s.attachments_ready != false {
        for i in 0..<MRT_NUM {
            sg.destroy_image(mrt_s.color_images[i])
            sg.destroy_view(mrt_s.offscreen_pass.attachments.colors[i])
            sg.destroy_view(mrt_s.display_bind.views[shaders.mrt_VIEW_tex0 + i])
        }
        sg.destroy_image(mrt_s.depth_image)
        sg.destroy_view(mrt_s.offscreen_pass.attachments.depth_stencil)
    }
}

// ---------------------------------------------------------------- blend
BLEND_NUM_FACTORS :: 15

blend_state :: struct {
    pass_action: sg.Pass_Action,
    bind:        sg.Bindings,
    pips:        [BLEND_NUM_FACTORS][BLEND_NUM_FACTORS]sg.Pipeline,
    bg_pip:      sg.Pipeline,
    r:           f32,
    quad_vs_params: shaders.blend_Quad_Vs_Params,
    bg_fs_params:   shaders.blend_Bg_Fs_Params,
}
blend_s: blend_state

blend_init :: proc() {
    blend_s.pass_action = {colors = {0 = {load_action = .DONTCARE}}}
    vertices := [28]f32{
        -1.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.5,
        1.0, -1.0, 0.0, 0.0, 1.0, 0.0, 0.5,
        -1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.5,
        1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.5,
    }
    blend_s.bind.vertex_buffers[0] = sg.make_buffer(&sg.Buffer_Desc{
        data = sg.range_of(raw_data(&vertices), size_of(vertices)),
        label = "blend-quad-vertices",
    })
    blend_bg_shd_desc := shaders.blend_bg_shader_desc(sg.query_backend())
    blend_quad_shd_desc := shaders.blend_quad_shader_desc(sg.query_backend())
    blend_s.bg_pip = sg.make_pipeline(&sg.Pipeline_Desc{
        layout = {
            buffers = {0 = {stride = 28}},
            attrs = {shaders.blend_ATTR_bg_position = {format = .FLOAT2}},
        },
        shader = sg.make_shader(&blend_bg_shd_desc),
        primitive_type = .TRIANGLE_STRIP,
        label = "blend-bg-pipeline",
    })
    pip_desc := sg.Pipeline_Desc{
        layout = {
            attrs = {
                shaders.blend_ATTR_quad_position = {format = .FLOAT3},
                shaders.blend_ATTR_quad_color0 = {format = .FLOAT4},
            },
        },
        shader = sg.make_shader(&blend_quad_shd_desc),
        primitive_type = .TRIANGLE_STRIP,
        blend_color = {1.0, 0.0, 0.0, 1.0},
        label = "blend-pipeline",
    }
    for src in 0..<BLEND_NUM_FACTORS {
        for dst in 0..<BLEND_NUM_FACTORS {
            src_blend := sg.Blend_Factor(u32(src + 1))
            dst_blend := sg.Blend_Factor(u32(dst + 1))
            if src_blend == .BLEND_COLOR || src_blend == .ONE_MINUS_BLEND_COLOR {
                if dst_blend == .BLEND_ALPHA || dst_blend == .ONE_MINUS_BLEND_ALPHA {
                    continue
                }
            } else if src_blend == .BLEND_ALPHA || src_blend == .ONE_MINUS_BLEND_ALPHA {
                if dst_blend == .BLEND_COLOR || dst_blend == .ONE_MINUS_BLEND_COLOR {
                    continue
                }
            }
            pip_desc.colors[0].blend = {
                enabled = true,
                src_factor_rgb = src_blend,
                dst_factor_rgb = dst_blend,
                src_factor_alpha = .ONE,
                dst_factor_alpha = .ZERO,
            }
            blend_s.pips[src][dst] = sg.make_pipeline(&pip_desc)
        }
    }
}

blend_frame :: proc(w, h: i32) {
    proj := mat4_perspective(1.5707964, f32(w) / f32(h), 0.01, 100.0)
    view := mat4_look_at({0, 0, 20.0}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    sample_begin_pass(&blend_s.pass_action, w, h)
    sg.apply_pipeline(blend_s.bg_pip)
    sg.apply_bindings(&blend_s.bind)
    ur9 := sg.range_of(rawptr(&blend_s.bg_fs_params), size_of(blend_s.bg_fs_params))
	sg.apply_uniforms(shaders.blend_UB_bg_fs_params, &ur9)
    sg.draw(0, 4, 1)
    r0 := blend_s.r
    for src in 0..<BLEND_NUM_FACTORS {
        for dst in 0..<BLEND_NUM_FACTORS {
            if blend_s.pips[src][dst].id == sg.INVALID_ID {
                continue
            }
            rm := mat4_rotation_y(r0)
            x := (f32(dst - BLEND_NUM_FACTORS / 2)) * 3.0
            y := (f32(src - BLEND_NUM_FACTORS / 2)) * 2.2
            model := mat4_mul(rm, mat4_translation(x, y, 0.0))
            blend_s.quad_vs_params.mvp = mat4_mul(model, view_proj)
            sg.apply_pipeline(blend_s.pips[src][dst])
            sg.apply_bindings(&blend_s.bind)
            ur10 := sg.range_of(rawptr(&blend_s.quad_vs_params), size_of(blend_s.quad_vs_params))
	sg.apply_uniforms(shaders.blend_UB_quad_vs_params, &ur10)
            sg.draw(0, 4, 1)
            r0 += 0.6
        }
    }
    sg.end_pass()
    sg.commit()
    t := frame_dt * 60.0
    blend_s.r += 0.6 * t
    blend_s.bg_fs_params.tick += 1.0 * t
}

blend_shutdown :: proc() {
    for src in 0..<BLEND_NUM_FACTORS {
        for dst in 0..<BLEND_NUM_FACTORS {
            if blend_s.pips[src][dst].id != sg.INVALID_ID {
                sg.destroy_pipeline(blend_s.pips[src][dst])
            }
        }
    }
    sg.destroy_pipeline(blend_s.bg_pip)
    sg.destroy_buffer(blend_s.bind.vertex_buffers[0])
}

// ---------------------------------------------------------------- shapes
Shape_Entry :: struct {
    pos:  [3]f32,
    draw: sshape.Element_Range,
}

Shape_Kind :: enum {
    BOX,
    PLANE,
    SPHERE,
    CYLINDER,
    TORUS,
    NUM_SHAPES,
}

shapes_state :: struct {
    pass_action: sg.Pass_Action,
    pip:         sg.Pipeline,
    vbuf:        sg.Buffer,
    ibuf:        sg.Buffer,
    shapes:      [5]Shape_Entry,
    vs_params:   shaders.shapes_Vs_Params,
    rx, ry:      f32,
}
shapes_s: shapes_state

shapes_vertices_buf: [6 * 1024 * 24]u8
shapes_indices_buf: [16 * 1024]u16

shapes_init :: proc() {
    sdtx.setup(&sdtx.Desc{fonts = {0 = sdtx.font_oric()}})
    shapes_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0, 0, 0, 1}}}}
    shapes_s.shapes[int(Shape_Kind.BOX)].pos = {-1.0, 1.0, 0.0}
    shapes_s.shapes[int(Shape_Kind.PLANE)].pos = {1.0, 1.0, 0.0}
    shapes_s.shapes[int(Shape_Kind.SPHERE)].pos = {-2.0, -1.0, 0.0}
    shapes_s.shapes[int(Shape_Kind.CYLINDER)].pos = {2.0, -1.0, 0.0}
    shapes_s.shapes[int(Shape_Kind.TORUS)].pos = {0.0, -1.0, 0.0}
    shp := sshape.State{
        vertices = {buffer = sshape.range_of(raw_data(&shapes_vertices_buf), size_of(shapes_vertices_buf))},
        indices = {buffer = sshape.range_of(raw_data(&shapes_indices_buf), size_of(shapes_indices_buf))},
    }
    sshape.build_box(&shp, &sshape.Box{width = 1.0, height = 1.0, depth = 1.0, tiles = 10, random_colors = true})
    shapes_s.shapes[int(Shape_Kind.BOX)].draw = sshape.element_range(&shp)
    sshape.build_plane(&shp, &sshape.Plane{width = 1.0, depth = 1.0, tiles = 10, random_colors = true})
    shapes_s.shapes[int(Shape_Kind.PLANE)].draw = sshape.element_range(&shp)
    sshape.build_sphere(&shp, &sshape.Sphere{radius = 0.75, slices = 36, stacks = 20, random_colors = true})
    shapes_s.shapes[int(Shape_Kind.SPHERE)].draw = sshape.element_range(&shp)
    sshape.build_cylinder(&shp, &sshape.Cylinder{radius = 0.5, height = 1.5, slices = 36, stacks = 10, random_colors = true})
    shapes_s.shapes[int(Shape_Kind.CYLINDER)].draw = sshape.element_range(&shp)
    sshape.build_torus(&shp, &sshape.Torus{radius = 0.5, ring_radius = 0.3, rings = 36, sides = 18, random_colors = true})
    shapes_s.shapes[int(Shape_Kind.TORUS)].draw = sshape.element_range(&shp)
    assert(shp.valid != false)
    vbuf_desc := sshape.vertex_buffer_desc(&shp)
    ibuf_desc := sshape.index_buffer_desc(&shp)
    shapes_s.vbuf = sg.make_buffer(&vbuf_desc)
    shapes_s.ibuf = sg.make_buffer(&ibuf_desc)
    shapes_shd_desc := shaders.shapes_shapes_shader_desc(sg.query_backend())
    shapes_s.pip = sg.make_pipeline(&sg.Pipeline_Desc{
        shader = sg.make_shader(&shapes_shd_desc),
        layout = {
            buffers = {0 = sshape.vertex_buffer_layout_state(&shp)},
            attrs = {
                0 = sshape.position_vertex_attr_state(&shp),
                1 = sshape.normal_vertex_attr_state(&shp),
                2 = sshape.texcoord_vertex_attr_state(&shp),
                3 = sshape.color_vertex_attr_state(&shp),
            },
        },
        index_type = .UINT16,
        cull_mode = .NONE,
        depth = {compare = .LESS_EQUAL, write_enabled = true},
        label = "shapes-pipeline",
    })
}

shapes_frame :: proc(w, h: i32) {
    sdtx.canvas(f32(w) * 0.5, f32(h) * 0.5)
    sdtx.pos(0.5, 0.5)
    sdtx.puts("sokol shapes: normals, texcoords, vertex colors\n")
    proj := mat4_perspective(1.0471976, f32(w) / f32(h), 0.01, 10.0)
    view := mat4_look_at({0, 1.5, 4.0}, {0, 0, 0}, {0, 1, 0})
    view_proj := mat4_mul(view, proj)
    t := frame_dt * 60.0
    shapes_s.rx += 1.0 * t
    shapes_s.ry += 2.0 * t
    rm := mat4_mul(mat4_rotation_y(shapes_s.ry), mat4_rotation_x(shapes_s.rx))
    sample_begin_pass(&shapes_s.pass_action, w, h)
    sg.apply_pipeline(shapes_s.pip)
    sg.apply_bindings(&sg.Bindings{vertex_buffers = {0 = shapes_s.vbuf}, index_buffer = shapes_s.ibuf})
    for i in 0..<int(Shape_Kind.NUM_SHAPES) {
        model := mat4_mul(rm, mat4_translation(shapes_s.shapes[i].pos[0], shapes_s.shapes[i].pos[1], shapes_s.shapes[i].pos[2]))
        shapes_s.vs_params.mvp = mat4_mul(model, view_proj)
        ur11 := sg.range_of(rawptr(&shapes_s.vs_params), size_of(shapes_s.vs_params))
	sg.apply_uniforms(shaders.shapes_UB_vs_params, &ur11)
        sg.draw(shapes_s.shapes[i].draw.base_element, shapes_s.shapes[i].draw.num_elements, 1)
    }
    sdtx.draw()
    sg.end_pass()
    sg.commit()
}

shapes_shutdown :: proc() {
    sdtx.shutdown()
    sg.destroy_pipeline(shapes_s.pip)
    sg.destroy_buffer(shapes_s.vbuf)
    sg.destroy_buffer(shapes_s.ibuf)
}

// ---------------------------------------------------------------- sgl
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

// ---------------------------------------------------------------- debugtext
FONT_KC853 :: 0
FONT_KC854 :: 1
FONT_Z1013 :: 2
FONT_CPC :: 3
FONT_C64 :: 4
FONT_ORIC :: 5

debugtext_state :: struct {
    pass_action: sg.Pass_Action,
}
sdtx_s: debugtext_state

debugtext_init :: proc() {
    sdtx.setup(&sdtx.Desc{
        fonts = {
            FONT_KC853 = sdtx.font_kc853(),
            FONT_KC854 = sdtx.font_kc854(),
            FONT_Z1013 = sdtx.font_z1013(),
            FONT_CPC = sdtx.font_cpc(),
            FONT_C64 = sdtx.font_c64(),
            FONT_ORIC = sdtx.font_oric(),
        },
    })
    sdtx_s.pass_action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.0, 0.125, 0.25, 1.0}}}}
}

debugtext_print_font :: proc(font_index: u32, title: cstring, r, g, b: u8) {
    sdtx.font(font_index)
    sdtx.color3b(r, g, b)
    sdtx.puts(title)
    for c in 32..<256 {
        sdtx.putc(u8(c))
        if ((c + 1) & 63) == 0 {
            sdtx.crlf()
        }
    }
    sdtx.crlf()
}

debugtext_frame :: proc(w, h: i32) {
    sdtx.canvas(f32(w) * 0.5, f32(h) * 0.5)
    sdtx.origin(0.0, 2.0)
    sdtx.home()
    debugtext_print_font(FONT_KC853, "KC85/3:\n", 0xf4, 0x43, 0x36)
    debugtext_print_font(FONT_KC854, "KC85/4:\n", 0x21, 0x96, 0xf3)
    debugtext_print_font(FONT_Z1013, "Z1013:\n", 0x4c, 0xaf, 0x50)
    debugtext_print_font(FONT_CPC, "Amstrad CPC:\n", 0xff, 0xeb, 0x3b)
    debugtext_print_font(FONT_C64, "C64:\n", 0x79, 0x86, 0xcb)
    debugtext_print_font(FONT_ORIC, "Oric Atmos:\n", 0xff, 0x98, 0x00)
    sample_begin_pass(&sdtx_s.pass_action, w, h)
    sdtx.draw()
    sg.end_pass()
    sg.commit()
}

debugtext_shutdown :: proc() {
    sdtx.shutdown()
}
