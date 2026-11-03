package app

import sg "libs:sg"
import shaders "libs:shaders"

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
