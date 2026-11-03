package app

import sg "libs:sg"
import shaders "libs:shaders"

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
