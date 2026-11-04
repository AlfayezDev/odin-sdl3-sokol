package app

import sg "libs:sg"
import shaders "gen:shaders"

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
