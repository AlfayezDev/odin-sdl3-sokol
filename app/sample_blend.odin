package app

import sg "libs:sg"
import shaders "libs:shaders"

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
