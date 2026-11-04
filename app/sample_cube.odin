package app

import sg "libs:sg"
import shaders "gen:shaders"

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
