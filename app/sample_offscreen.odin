package app

import sg "libs:sg"
import sshape "libs:sshape"
import shaders "gen:shaders"

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
