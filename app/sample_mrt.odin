package app

import math "core:math"
import sg "libs:sg"
import shaders "gen:shaders"

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
