package app

import sdtx "libs:sdtx"
import sg "libs:sg"
import sshape "libs:sshape"
import shaders "libs:shaders"

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
