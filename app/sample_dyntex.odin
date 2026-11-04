package app

import sg "libs:sg"
import shaders "gen:shaders"

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
