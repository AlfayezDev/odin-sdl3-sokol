// Dependency-free ports of floooh/sokol-samples (sapp/) to the shim
// platform layer. sapp_width/height -> frame args, sapp_frame_duration ->
// shim_dt(), sglue_swapchain -> the shared begin_pass helper, dbgui dropped.
// sokol_gfx impl lives in sokol_shim.c; sokol_gl/debugtext impls live here.
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "sokol_shim.h"
#include "samples.h"
#include "sokol/sokol_gfx.h" // declarations only (impl in sokol_shim.c)
#if defined(SHIM_GLES3)
#define SOKOL_GLES3
#else
#define SOKOL_GLCORE
#endif

#define SOKOL_GL_IMPL
#define SOKOL_SHAPE_IMPL
#include "sokol/sokol_gl.h"
#include "sokol/sokol_shape.h"
#define SOKOL_DEBUGTEXT_IMPL
#include "sokol/sokol_debugtext.h"

#define VECMATH_GENERICS
#include "libs/vecmath.h"

#include "sample_quad_shaders.h"
#include "sample_mandelbrot_shaders.h"
#include "sample_cube_shaders.h"
#include "sample_instancing_shaders.h"
#include "sample_offscreen_shaders.h"
#include "sample_dyntex_shaders.h"
#include "sample_mrt_shaders.h"
#include "sample_blend_shaders.h"
#include "sample_shapes_shaders.h"

// shared: begin the default pass with the sample's pass action
static void sample_begin_pass(sg_pass_action *pa, int w, int h)
{
    sg_begin_pass(&(sg_pass){
        .action = *pa,
        .swapchain = {.width = w, .height = h},
    });
}

// ---------------------------------------------------------------- quad
static struct {
    sg_pass_action pass_action;
    sg_pipeline pip;
    sg_bindings bind;
} quad_state;

static void quad_init(void)
{
    float vertices[] = {
        // positions            colors
        -0.5f, 0.5f, 0.5f,      1.0f, 0.0f, 0.0f, 1.0f,
        0.5f, 0.5f, 0.5f,       0.0f, 1.0f, 0.0f, 1.0f,
        0.5f, -0.5f, 0.5f,      0.0f, 0.0f, 1.0f, 1.0f,
        -0.5f, -0.5f, 0.5f,     1.0f, 1.0f, 0.0f, 1.0f,
    };
    quad_state.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(vertices),
        .label = "quad-vertices",
    });
    uint16_t indices[] = {0, 1, 2, 0, 2, 3};
    quad_state.bind.index_buffer = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data = SG_RANGE(indices),
        .label = "quad-indices",
    });
    quad_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(quad_quad_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .layout = {
            .attrs = {
                [quad_ATTR_quad_position].format = SG_VERTEXFORMAT_FLOAT3,
                [quad_ATTR_quad_color0].format = SG_VERTEXFORMAT_FLOAT4,
            },
        },
        .label = "quad-pipeline",
    });
    quad_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.0f, 1.0f}},
    };
}

static void quad_frame(int w, int h)
{
    sample_begin_pass(&quad_state.pass_action, w, h);
    sg_apply_pipeline(quad_state.pip);
    sg_apply_bindings(&quad_state.bind);
    sg_draw(0, 6, 1);
    sg_end_pass();
    sg_commit();
}

static void quad_shutdown(void)
{
    sg_destroy_pipeline(quad_state.pip);
    sg_destroy_buffer(quad_state.bind.vertex_buffers[0]);
    sg_destroy_buffer(quad_state.bind.index_buffer);
}

// ---------------------------------------------------------------- mandelbrot
static struct {
    sg_pipeline pip;
    float time;
} mandelbrot_state;

static void mandelbrot_init(void)
{
    mandelbrot_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(mandelbrot_mandelbrot_shader_desc(sg_query_backend())),
        .label = "mandelbrot-pipeline",
    });
}

static void mandelbrot_frame(int w, int h)
{
    mandelbrot_state.time = fmodf(mandelbrot_state.time + shim_dt(), 20.0f);
    const float aspect = (float)w / (float)h;
    const float width = 4.0f * powf(0.6f, mandelbrot_state.time);
    int iter_max = 64 + (int)(log2f(4.0f / width) * 32.0f);
    if (iter_max > 256)
    {
        iter_max = 256;
    }
    const mandelbrot_fs_params_t fs_params = {
        .time = mandelbrot_state.time,
        .width = width,
        .iter_max = iter_max,
        .aspect = {
            [0] = aspect >= 1.0f ? aspect : 1.0f,
            [1] = aspect >= 1.0f ? 1.0f : 1.0f / aspect,
        },
    };
    sg_begin_pass(&(sg_pass){
        .action.colors[0].load_action = SG_LOADACTION_DONTCARE,
        .swapchain = {.width = w, .height = h},
    });
    sg_apply_pipeline(mandelbrot_state.pip);
    sg_apply_uniforms(mandelbrot_UB_fs_params, &SG_RANGE(fs_params));
    sg_draw(0, 3, 1);
    sg_end_pass();
    sg_commit();
}

static void mandelbrot_shutdown(void)
{
    sg_destroy_pipeline(mandelbrot_state.pip);
}

// ---------------------------------------------------------------- 3d helpers
// model-view-projection used by cube/dyntex-style samples
static mat44_t sample_mvp(float rx, float ry, float w, float h, float eye_dist)
{
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(60.0f), w / h, 0.01f, 10.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 1.5f, eye_dist), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    const mat44_t rxm = mat44_rotation_x(vm_radians(rx));
    const mat44_t rym = mat44_rotation_y(vm_radians(ry));
    const mat44_t model = vm_mul(rym, rxm);
    return vm_mul(model, view_proj);
}

// ---------------------------------------------------------------- cube
static struct {
    float rx, ry;
    sg_pipeline pip;
    sg_bindings bind;
} cube_state;

static void cube_init(void)
{
    float vertices[] = {
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
    };
    sg_buffer vbuf = sg_make_buffer(&(sg_buffer_desc){.data = SG_RANGE(vertices), .label = "cube-vertices"});
    uint16_t indices[] = {
        0, 1, 2, 0, 2, 3,
        6, 5, 4, 7, 6, 4,
        8, 9, 10, 8, 10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20
    };
    sg_buffer ibuf = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data = SG_RANGE(indices),
        .label = "cube-indices",
    });
    cube_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .buffers[0].stride = 28,
            .attrs = {
                [cube_ATTR_cube_position].format = SG_VERTEXFORMAT_FLOAT3,
                [cube_ATTR_cube_color0].format = SG_VERTEXFORMAT_FLOAT4,
            },
        },
        .shader = sg_make_shader(cube_cube_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .depth = {.write_enabled = true, .compare = SG_COMPAREFUNC_LESS_EQUAL},
        .label = "cube-pipeline",
    });
    cube_state.bind = (sg_bindings){
        .vertex_buffers[0] = vbuf,
        .index_buffer = ibuf,
    };
}

static void cube_frame(int w, int h)
{
    const float t = shim_dt() * 60.0f;
    cube_state.rx += 1.0f * t;
    cube_state.ry += 2.0f * t;
    const cube_vs_params_t vs_params = {.mvp = sample_mvp(cube_state.rx, cube_state.ry, (float)w, (float)h, 4.0f)};
    sg_pass_action pa = {
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.25f, 0.5f, 0.75f, 1.0f}},
    };
    sample_begin_pass(&pa, w, h);
    sg_apply_pipeline(cube_state.pip);
    sg_apply_bindings(&cube_state.bind);
    sg_apply_uniforms(cube_UB_vs_params, &SG_RANGE(vs_params));
    sg_draw(0, 36, 1);
    sg_end_pass();
    sg_commit();
}

static void cube_shutdown(void)
{
    sg_destroy_pipeline(cube_state.pip);
    sg_destroy_buffer(cube_state.bind.vertex_buffers[0]);
    sg_destroy_buffer(cube_state.bind.index_buffer);
}

// ---------------------------------------------------------------- instancing
#define MAX_PARTICLES (512 * 1024)
#define NUM_PARTICLES_EMITTED_PER_FRAME (10)

static struct {
    sg_pass_action pass_action;
    sg_pipeline pip;
    sg_bindings bind;
    float ry;
    int cur_num_particles;
    vec3_t pos[MAX_PARTICLES];
    vec3_t vel[MAX_PARTICLES];
} inst_state;

static uint32_t inst_xorshift32(void)
{
    static uint32_t x = 0x12345678;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

static void instancing_init(void)
{
    inst_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.0f, 1.0f}},
    };
    const float r = 0.05f;
    const float vertices[] = {
        0.0f, -r, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f,
        r, 0.0f, r, 0.0f, 1.0f, 0.0f, 1.0f,
        r, 0.0f, -r, 0.0f, 0.0f, 1.0f, 1.0f,
        -r, 0.0f, -r, 1.0f, 1.0f, 0.0f, 1.0f,
        -r, 0.0f, r, 0.0f, 1.0f, 1.0f, 1.0f,
        0.0f, r, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f,
    };
    inst_state.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(vertices),
        .label = "geometry-vertices",
    });
    const uint16_t indices[] = {
        0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1,
        5, 1, 2, 5, 2, 3, 5, 3, 4, 5, 4, 1
    };
    inst_state.bind.index_buffer = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data = SG_RANGE(indices),
        .label = "geometry-indices",
    });
    inst_state.bind.vertex_buffers[1] = sg_make_buffer(&(sg_buffer_desc){
        .size = sizeof(inst_state.pos),
        .usage.write_transient = true,
        .label = "instance-data",
    });
    inst_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE,
            .attrs = {
                [instancing_ATTR_instancing_pos] = {.format = SG_VERTEXFORMAT_FLOAT3, .buffer_index = 0},
                [instancing_ATTR_instancing_color0] = {.format = SG_VERTEXFORMAT_FLOAT4, .buffer_index = 0},
                [instancing_ATTR_instancing_inst_pos] = {.format = SG_VERTEXFORMAT_FLOAT3, .buffer_index = 1},
            },
        },
        .shader = sg_make_shader(instancing_instancing_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .depth = {.compare = SG_COMPAREFUNC_LESS_EQUAL, .write_enabled = true},
        .label = "instancing-pipeline",
    });
}

static void instancing_frame(int w, int h)
{
    const float frame_time_s = shim_dt();
    for (int i = 0; i < NUM_PARTICLES_EMITTED_PER_FRAME; i++)
    {
        if (inst_state.cur_num_particles < MAX_PARTICLES)
        {
            inst_state.pos[inst_state.cur_num_particles] = vec3(0.0, 0.0, 0.0);
            inst_state.vel[inst_state.cur_num_particles] = vec3(
                ((float)(inst_xorshift32() & 0x7FFF) / 0x7FFF) - 0.5f,
                ((float)(inst_xorshift32() & 0x7FFF) / 0x7FFF) * 0.5f + 2.0f,
                ((float)(inst_xorshift32() & 0x7FFF) / 0x7FFF) - 0.5f);
            inst_state.cur_num_particles++;
        }
        else
        {
            break;
        }
    }
    for (int i = 0; i < inst_state.cur_num_particles; i++)
    {
        inst_state.vel[i].y -= 1.0f * frame_time_s;
        inst_state.pos[i].x += inst_state.vel[i].x * frame_time_s;
        inst_state.pos[i].y += inst_state.vel[i].y * frame_time_s;
        inst_state.pos[i].z += inst_state.vel[i].z * frame_time_s;
        if (inst_state.pos[i].y < -2.0f)
        {
            inst_state.pos[i].y = -1.8f;
            inst_state.vel[i].y = -inst_state.vel[i].y;
            inst_state.vel[i].x *= 0.8f;
            inst_state.vel[i].y *= 0.8f;
            inst_state.vel[i].z *= 0.8f;
        }
    }
    sg_write_buffer_transient(&(sg_write_buffer_desc){
        .src.data = SG_RANGE(inst_state.pos),
        .dst.buffer = inst_state.bind.vertex_buffers[1],
        .size = (size_t)inst_state.cur_num_particles * sizeof(vec3_t),
    });
    const float aspect = (float)w / (float)h;
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(60.0f), aspect, 0.01f, 50.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 1.5f, 8.0f), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    inst_state.ry += 60.0f * frame_time_s;
    const instancing_vs_params_t vs_params = {
        .mvp = vm_mul(mat44_rotation_y(vm_radians(inst_state.ry)), view_proj),
    };
    sample_begin_pass(&inst_state.pass_action, w, h);
    sg_apply_pipeline(inst_state.pip);
    sg_apply_bindings(&inst_state.bind);
    sg_apply_uniforms(instancing_UB_vs_params, &SG_RANGE(vs_params));
    sg_draw(0, 24, inst_state.cur_num_particles);
    sg_end_pass();
    sg_commit();
}

static void instancing_shutdown(void)
{
    sg_destroy_pipeline(inst_state.pip);
    sg_destroy_buffer(inst_state.bind.vertex_buffers[0]);
    sg_destroy_buffer(inst_state.bind.index_buffer);
    sg_destroy_buffer(inst_state.bind.vertex_buffers[1]);
}

// ---------------------------------------------------------------- offscreen
#define OFFSCREEN_COLOR_FORMAT (SG_PIXELFORMAT_RGBA8)
#define OFFSCREEN_DEPTH_FORMAT (SG_PIXELFORMAT_DEPTH)

static struct {
    struct {
        sg_pass pass;
        sg_pipeline pip;
        sg_bindings bind;
    } offscreen;
    struct {
        sg_pass_action pass_action;
        sg_pipeline pip;
        sg_bindings bind;
    } display;
    sshape_element_range_t donut;
    sshape_element_range_t sphere;
    float rx, ry;
    sg_image color_img, depth_img;
    sg_sampler smp;
} off_state;

static mat44_t offscreen_mvp(float rx, float ry, float aspect, float eye_dist)
{
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(45.0f), aspect, 0.01f, 10.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 0.0f, eye_dist), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    const mat44_t rxm = mat44_rotation_x(vm_radians(rx));
    const mat44_t rym = mat44_rotation_y(vm_radians(ry));
    const mat44_t model = vm_mul(rxm, rym);
    return vm_mul(model, view_proj);
}

static void offscreen_init(void)
{
    off_state.display.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.25f, 0.45f, 0.65f, 1.0f}},
    };
    sg_image_desc img_desc = {
        .usage = {.color_attachment = true},
        .width = 256,
        .height = 256,
        .pixel_format = OFFSCREEN_COLOR_FORMAT,
        .sample_count = 1,
        .label = "color-image",
    };
    sg_image color_img = sg_make_image(&img_desc);
    img_desc.pixel_format = OFFSCREEN_DEPTH_FORMAT;
    img_desc.usage = (sg_image_usage){.depth_stencil_attachment = true};
    img_desc.label = "depth-image";
    sg_image depth_img = sg_make_image(&img_desc);
    off_state.offscreen.pass = (sg_pass){
        .attachments = {
            .colors[0] = sg_make_view(&(sg_view_desc){
                .color_attachment = {.image = color_img},
                .label = "color-attachment",
            }),
            .depth_stencil = sg_make_view(&(sg_view_desc){
                .depth_stencil_attachment = {.image = depth_img},
                .label = "depth-attachment",
            }),
        },
        .action = {
            .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.25f, 0.25f, 0.25f, 1.0f}},
        },
        .label = "offscreen-pass",
    };
    uint8_t vertices[SSHAPE_MAX_VERTEX_SIZE * 4000] = {0};
    uint16_t indices[24000] = {0};
    sshape_state_t shp = {
        .disable.colors = true,
        .vertices.buffer = SSHAPE_RANGE(vertices),
        .indices.buffer = SSHAPE_RANGE(indices),
    };
    sshape_build_torus(&shp, &(sshape_torus_t){
        .radius = 0.5f,
        .ring_radius = 0.3f,
        .sides = 20,
        .rings = 36,
    });
    off_state.donut = sshape_element_range(&shp);
    sshape_build_sphere(&shp, &(sshape_sphere_t){
        .radius = 0.5f,
        .slices = 72,
        .stacks = 40,
    });
    off_state.sphere = sshape_element_range(&shp);
    sg_buffer_desc vbuf_desc = sshape_vertex_buffer_desc(&shp);
    sg_buffer_desc ibuf_desc = sshape_index_buffer_desc(&shp);
    vbuf_desc.label = "shape-vbuf";
    ibuf_desc.label = "shape-ibuf";
    sg_buffer vbuf = sg_make_buffer(&vbuf_desc);
    sg_buffer ibuf = sg_make_buffer(&ibuf_desc);
    off_state.offscreen.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .buffers[0] = sshape_vertex_buffer_layout_state(&shp),
            .attrs = {
                [offscreen_ATTR_offscreen_position] = sshape_position_vertex_attr_state(&shp),
                [offscreen_ATTR_offscreen_normal] = sshape_normal_vertex_attr_state(&shp),
            },
        },
        .shader = sg_make_shader(offscreen_offscreen_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .sample_count = 1,
        .depth = {
            .pixel_format = OFFSCREEN_DEPTH_FORMAT,
            .compare = SG_COMPAREFUNC_LESS_EQUAL,
            .write_enabled = true,
        },
        .colors[0].pixel_format = OFFSCREEN_COLOR_FORMAT,
        .label = "offscreen-pipeline",
    });
    off_state.display.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .buffers[0] = sshape_vertex_buffer_layout_state(&shp),
            .attrs = {
                [offscreen_ATTR_default_position] = sshape_position_vertex_attr_state(&shp),
                [offscreen_ATTR_default_normal] = sshape_normal_vertex_attr_state(&shp),
                [offscreen_ATTR_default_texcoord0] = sshape_texcoord_vertex_attr_state(&shp),
            },
        },
        .shader = sg_make_shader(offscreen_default_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .depth = {.compare = SG_COMPAREFUNC_LESS_EQUAL, .write_enabled = true},
        .label = "default-pipeline",
    });
    sg_sampler smp = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u = SG_WRAP_REPEAT,
        .wrap_v = SG_WRAP_REPEAT,
        .label = "sampler",
    });
    off_state.offscreen.bind = (sg_bindings){
        .vertex_buffers[0] = vbuf,
        .index_buffer = ibuf,
    };
    off_state.display.bind = (sg_bindings){
        .vertex_buffers[0] = vbuf,
        .index_buffer = ibuf,
        .views[offscreen_VIEW_tex] = sg_make_view(&(sg_view_desc){
            .texture = {.image = color_img},
            .label = "texture-view",
        }),
        .samplers[offscreen_SMP_smp] = smp,
    };
    off_state.color_img = color_img;
    off_state.depth_img = depth_img;
    off_state.smp = smp;
}

static void offscreen_frame(int w, int h)
{
    const float t = shim_dt() * 60.0f;
    off_state.rx += 1.0f * t;
    off_state.ry += 2.0f * t;
    offscreen_vs_params_t vs_params = {
        .mvp = offscreen_mvp(off_state.rx, off_state.ry, 1.0f, 2.5f),
    };
    sg_begin_pass(&off_state.offscreen.pass);
    sg_apply_pipeline(off_state.offscreen.pip);
    sg_apply_bindings(&off_state.offscreen.bind);
    sg_apply_uniforms(offscreen_UB_vs_params, &SG_RANGE(vs_params));
    sg_draw(off_state.donut.base_element, off_state.donut.num_elements, 1);
    sg_end_pass();
    vs_params = (offscreen_vs_params_t){
        .mvp = offscreen_mvp(-off_state.rx * 0.25f, off_state.ry * 0.25f, (float)w / (float)h, 1.5f),
    };
    sample_begin_pass(&off_state.display.pass_action, w, h);
    sg_apply_pipeline(off_state.display.pip);
    sg_apply_bindings(&off_state.display.bind);
    sg_apply_uniforms(offscreen_UB_vs_params, &SG_RANGE(vs_params));
    sg_draw(off_state.sphere.base_element, off_state.sphere.num_elements, 1);
    sg_end_pass();
    sg_commit();
}

static void offscreen_shutdown(void)
{
    sg_destroy_pipeline(off_state.offscreen.pip);
    sg_destroy_pipeline(off_state.display.pip);
    sg_destroy_buffer(off_state.offscreen.bind.vertex_buffers[0]);
    sg_destroy_buffer(off_state.offscreen.bind.index_buffer);
    sg_destroy_view(off_state.offscreen.pass.attachments.colors[0]);
    sg_destroy_view(off_state.offscreen.pass.attachments.depth_stencil);
    sg_destroy_view(off_state.display.bind.views[offscreen_VIEW_tex]);
    sg_destroy_image(off_state.color_img);
    sg_destroy_image(off_state.depth_img);
}

// ---------------------------------------------------------------- dyntex
#define DYNT_EX_IMAGE_WIDTH 128
#define DYNT_EX_IMAGE_HEIGHT 128
#define DYNT_LIVING (0xFFFFFFFF)
#define DYNT_DEAD (0xFF000000)

static struct {
    sg_pass_action pass_action;
    sg_pipeline pip;
    sg_image img;
    sg_bindings bind;
    float rx, ry;
    int update_count;
    uint32_t pixels[DYNT_EX_IMAGE_WIDTH][DYNT_EX_IMAGE_HEIGHT];
} dynt_state;

static void gol_init(void)
{
    for (int y = 0; y < DYNT_EX_IMAGE_HEIGHT; y++)
    {
        for (int x = 0; x < DYNT_EX_IMAGE_WIDTH; x++)
        {
            dynt_state.pixels[y][x] = ((rand() & 255) > 230) ? DYNT_LIVING : DYNT_DEAD;
        }
    }
}

static void gol_update(void)
{
    for (int y = 0; y < DYNT_EX_IMAGE_HEIGHT; y++)
    {
        for (int x = 0; x < DYNT_EX_IMAGE_WIDTH; x++)
        {
            int num_living_neighbours = 0;
            for (int ny = -1; ny < 2; ny++)
            {
                for (int nx = -1; nx < 2; nx++)
                {
                    if ((nx == 0) && (ny == 0))
                    {
                        continue;
                    }
                    if (dynt_state.pixels[(y + ny) & (DYNT_EX_IMAGE_HEIGHT - 1)][(x + nx) & (DYNT_EX_IMAGE_WIDTH - 1)] == DYNT_LIVING)
                    {
                        num_living_neighbours++;
                    }
                }
            }
            if (dynt_state.pixels[y][x] == DYNT_LIVING)
            {
                if (num_living_neighbours < 2 || num_living_neighbours > 3)
                {
                    dynt_state.pixels[y][x] = DYNT_DEAD;
                }
            }
            else if (num_living_neighbours == 3)
            {
                dynt_state.pixels[y][x] = DYNT_LIVING;
            }
        }
    }
    if (dynt_state.update_count++ > 240)
    {
        gol_init();
        dynt_state.update_count = 0;
    }
}

static void dyntex_init(void)
{
    dynt_state.img = sg_make_image(&(sg_image_desc){
        .usage.write_transient = true,
        .width = DYNT_EX_IMAGE_WIDTH,
        .height = DYNT_EX_IMAGE_HEIGHT,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .label = "dynamic-texture",
    });
    sg_view tex_view = sg_make_view(&(sg_view_desc){
        .texture = {.image = dynt_state.img},
        .label = "dynamic-texture-view",
    });
    sg_sampler smp = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
        .label = "sampler",
    });
    float vertices[] = {
        // pos                  color                       uvs
        -1.0f, -1.0f, -1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f,
        1.0f, -1.0f, -1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, -1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f,
        -1.0f, 1.0f, -1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f,
        -1.0f, -1.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f, 0.0f,
        1.0f, -1.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 1.0f,
        -1.0f, 1.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f, 1.0f,
        -1.0f, -1.0f, -1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f,
        -1.0f, 1.0f, -1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f, 0.0f,
        -1.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f,
        -1.0f, -1.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,
        1.0f, -1.0f, -1.0f, 1.0f, 0.5f, 0.0f, 1.0f, 0.0f, 0.0f,
        1.0f, 1.0f, -1.0f, 1.0f, 0.5f, 0.0f, 1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 1.0f, 1.0f, 0.5f, 0.0f, 1.0f, 1.0f, 1.0f,
        1.0f, -1.0f, 1.0f, 1.0f, 0.5f, 0.0f, 1.0f, 0.0f, 1.0f,
        -1.0f, -1.0f, -1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 0.0f, 0.0f,
        -1.0f, -1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 1.0f, 0.0f,
        1.0f, -1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, -1.0f, -1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 0.0f, 1.0f,
        -1.0f, 1.0f, -1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 0.0f, 0.0f,
        -1.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, -1.0f, 1.0f, 0.0f, 0.5f, 1.0f, 0.0f, 1.0f,
    };
    uint16_t indices[] = {
        0, 1, 2, 0, 2, 3,
        6, 5, 4, 7, 6, 4,
        8, 9, 10, 8, 10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20
    };
    sg_buffer vbuf = sg_make_buffer(&(sg_buffer_desc){.data = SG_RANGE(vertices), .label = "cube-vertices"});
    sg_buffer ibuf = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data = SG_RANGE(indices),
        .label = "cube-indices",
    });
    dynt_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .attrs = {
                [dyntex_ATTR_dyntex_position].format = SG_VERTEXFORMAT_FLOAT3,
                [dyntex_ATTR_dyntex_color0].format = SG_VERTEXFORMAT_FLOAT4,
                [dyntex_ATTR_dyntex_texcoord0].format = SG_VERTEXFORMAT_FLOAT2,
            },
        },
        .shader = sg_make_shader(dyntex_dyntex_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .depth = {.compare = SG_COMPAREFUNC_LESS_EQUAL, .write_enabled = true},
        .label = "dyntex-cube-pipeline",
    });
    dynt_state.bind = (sg_bindings){
        .vertex_buffers[0] = vbuf,
        .index_buffer = ibuf,
        .views[dyntex_VIEW_tex] = tex_view,
        .samplers[dyntex_SMP_smp] = smp,
    };
    dynt_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.0f, 1.0f}},
    };
    gol_init();
}

static void dyntex_frame(int w, int h)
{
    const float t = shim_dt() * 60.0f;
    dynt_state.rx += 1.0f * t;
    dynt_state.ry += 2.0f * t;
    const dyntex_vs_params_t vs_params = {.mvp = sample_mvp(dynt_state.rx, dynt_state.ry, (float)w, (float)h, 4.0f)};
    gol_update();
    sg_write_image_transient(&(sg_write_image_desc){
        .src.data = SG_RANGE(dynt_state.pixels),
        .dst.image = dynt_state.img,
    });
    sample_begin_pass(&dynt_state.pass_action, w, h);
    sg_apply_pipeline(dynt_state.pip);
    sg_apply_bindings(&dynt_state.bind);
    sg_apply_uniforms(dyntex_UB_vs_params, &SG_RANGE(vs_params));
    sg_draw(0, 36, 1);
    sg_end_pass();
    sg_commit();
}

static void dyntex_shutdown(void)
{
    sg_destroy_pipeline(dynt_state.pip);
    sg_destroy_buffer(dynt_state.bind.vertex_buffers[0]);
    sg_destroy_buffer(dynt_state.bind.index_buffer);
    sg_destroy_view(dynt_state.bind.views[dyntex_VIEW_tex]);
    sg_destroy_sampler(dynt_state.bind.samplers[dyntex_SMP_smp]);
    sg_destroy_image(dynt_state.img);
}

// ---------------------------------------------------------------- mrt
#define MRT_NUM (3)

static struct {
    struct {
        sg_pipeline pip;
        sg_bindings bind;
        sg_pass pass;
    } offscreen;
    struct {
        sg_pipeline pip;
        sg_bindings bind;
        sg_pass_action pass_action;
    } display;
    struct {
        sg_pipeline pip;
        sg_bindings bind;
    } dbg;
    struct {
        sg_image color[MRT_NUM];
        sg_image depth;
        sg_view color_view[MRT_NUM];
        sg_view depth_view;
    } images;
    float rx, ry;
    int cur_w, cur_h;
} mrt_state;

typedef struct {
    float x, y, z, b;
} mrt_vertex_t;

static void mrt_reinit_attachments(int width, int height)
{
    for (int i = 0; i < MRT_NUM; i++)
    {
        sg_uninit_image(mrt_state.images.color[i]);
        sg_uninit_view(mrt_state.offscreen.pass.attachments.colors[i]);
        sg_uninit_view(mrt_state.display.bind.views[mrt_VIEW_tex0 + i]);
    }
    sg_uninit_image(mrt_state.images.depth);
    sg_uninit_view(mrt_state.images.depth_view);

    for (int i = 0; i < MRT_NUM; i++)
    {
        sg_init_image(mrt_state.images.color[i], &(sg_image_desc){
            .usage.color_attachment = true,
            .width = width,
            .height = height,
            .sample_count = 1,
        });
        sg_init_view(mrt_state.offscreen.pass.attachments.colors[i], &(sg_view_desc){
            .color_attachment = {.image = mrt_state.images.color[i]},
        });
        sg_init_view(mrt_state.display.bind.views[mrt_VIEW_tex0 + i], &(sg_view_desc){
            .texture = {.image = mrt_state.images.color[i]},
        });
    }
    sg_init_image(mrt_state.images.depth, &(sg_image_desc){
        .usage.depth_stencil_attachment = true,
        .width = width,
        .height = height,
        .pixel_format = SG_PIXELFORMAT_DEPTH,
        .sample_count = 1,
    });
    sg_init_view(mrt_state.images.depth_view, &(sg_view_desc){
        .depth_stencil_attachment = {.image = mrt_state.images.depth},
    });
    mrt_state.offscreen.pass.attachments.depth_stencil = mrt_state.images.depth_view;
    mrt_state.cur_w = width;
    mrt_state.cur_h = height;
}

static void mrt_init(void)
{
    mrt_state.display.pass_action = (sg_pass_action){
        .colors[0].load_action = SG_LOADACTION_DONTCARE,
        .depth.load_action = SG_LOADACTION_DONTCARE,
        .stencil.load_action = SG_LOADACTION_DONTCARE,
    };
    for (int i = 0; i < MRT_NUM; i++)
    {
        mrt_state.images.color[i] = sg_alloc_image();
        mrt_state.offscreen.pass.attachments.colors[i] = sg_alloc_view();
        mrt_state.display.bind.views[mrt_VIEW_tex0 + i] = sg_alloc_view();
    }
    mrt_state.images.depth = sg_alloc_image();
    mrt_state.images.depth_view = sg_alloc_view();

    mrt_vertex_t cube_vertices[] = {
        {-1.0f, -1.0f, -1.0f, 1.0f}, {1.0f, -1.0f, -1.0f, 1.0f}, {1.0f, 1.0f, -1.0f, 1.0f}, {-1.0f, 1.0f, -1.0f, 1.0f},
        {-1.0f, -1.0f, 1.0f, 0.8f}, {1.0f, -1.0f, 1.0f, 0.8f}, {1.0f, 1.0f, 1.0f, 0.8f}, {-1.0f, 1.0f, 1.0f, 0.8f},
        {-1.0f, -1.0f, -1.0f, 0.6f}, {-1.0f, 1.0f, -1.0f, 0.6f}, {-1.0f, 1.0f, 1.0f, 0.6f}, {-1.0f, -1.0f, 1.0f, 0.6f},
        {1.0f, -1.0f, -1.0f, 0.4f}, {1.0f, 1.0f, -1.0f, 0.4f}, {1.0f, 1.0f, 1.0f, 0.4f}, {1.0f, -1.0f, 1.0f, 0.4f},
        {-1.0f, -1.0f, -1.0f, 0.5f}, {-1.0f, -1.0f, 1.0f, 0.5f}, {1.0f, -1.0f, 1.0f, 0.5f}, {1.0f, -1.0f, -1.0f, 0.5f},
        {-1.0f, 1.0f, -1.0f, 0.7f}, {-1.0f, 1.0f, 1.0f, 0.7f}, {1.0f, 1.0f, 1.0f, 0.7f}, {1.0f, 1.0f, -1.0f, 0.7f},
    };
    mrt_state.offscreen.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(cube_vertices),
        .label = "cube vertices",
    });
    uint16_t cube_indices[] = {
        0, 1, 2, 0, 2, 3,
        6, 5, 4, 7, 6, 4,
        8, 9, 10, 8, 10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20
    };
    mrt_state.offscreen.bind.index_buffer = sg_make_buffer(&(sg_buffer_desc){
        .usage.index_buffer = true,
        .data = SG_RANGE(cube_indices),
        .label = "cube indices",
    });
    mrt_state.offscreen.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(mrt_offscreen_shader_desc(sg_query_backend())),
        .layout = {
            .buffers[0].stride = sizeof(mrt_vertex_t),
            .attrs = {
                [mrt_ATTR_offscreen_pos] = {.offset = offsetof(mrt_vertex_t, x), .format = SG_VERTEXFORMAT_FLOAT3},
                [mrt_ATTR_offscreen_bright0] = {.offset = offsetof(mrt_vertex_t, b), .format = SG_VERTEXFORMAT_FLOAT},
            },
        },
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_BACK,
        .sample_count = 1,
        .depth = {
            .pixel_format = SG_PIXELFORMAT_DEPTH,
            .compare = SG_COMPAREFUNC_LESS_EQUAL,
            .write_enabled = true,
        },
        .color_count = MRT_NUM,
        .label = "mrt offscreen pipeline",
    });
    mrt_state.offscreen.pass.action = (sg_pass_action){
        .colors = {
            [0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.25f, 0.0f, 0.0f, 1.0f}},
            [1] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.25f, 0.0f, 1.0f}},
            [2] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.25f, 1.0f}},
        },
    };
    float quad_vertices[] = {0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f};
    const sg_buffer quad_vbuf = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(quad_vertices),
        .label = "quad vertices",
    });
    mrt_state.display.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(mrt_fsq_shader_desc(sg_query_backend())),
        .layout = {.attrs[mrt_ATTR_fsq_pos].format = SG_VERTEXFORMAT_FLOAT2},
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP,
        .label = "fsq pipeline",
    });
    const sg_sampler smp = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
        .label = "mrt sampler",
    });
    mrt_state.display.bind.vertex_buffers[0] = quad_vbuf;
    mrt_state.display.bind.samplers[mrt_SMP_smp] = smp;
    mrt_state.dbg.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(mrt_dbg_shader_desc(sg_query_backend())),
        .layout = {.attrs[mrt_ATTR_dbg_pos].format = SG_VERTEXFORMAT_FLOAT2},
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP,
        .label = "dbg pipeline",
    });
    mrt_state.dbg.bind = (sg_bindings){
        .vertex_buffers[0] = quad_vbuf,
        .samplers[mrt_SMP_smp] = smp,
    };
}

static void mrt_frame(int w, int h)
{
    if (w != mrt_state.cur_w || h != mrt_state.cur_h)
    {
        mrt_reinit_attachments(w, h);
    }
    const float t = shim_dt() * 60.0f;
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(45.0f), (float)w / (float)h, 0.01f, 10.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 1.5f, 4.0f), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    mrt_state.rx += 1.0f * t;
    mrt_state.ry += 2.0f * t;
    const mat44_t rxm = mat44_rotation_x(vm_radians(mrt_state.rx));
    const mat44_t rym = mat44_rotation_y(vm_radians(mrt_state.ry));
    const mat44_t model = vm_mul(rym, rxm);
    const mrt_offscreen_params_t offscreen_params = {.mvp = vm_mul(model, view_proj)};
    const mrt_fsq_params_t fsq_params = {
        .offset = {sinf(mrt_state.rx * 0.01f) * 0.1f, sinf(mrt_state.ry * 0.01f) * 0.1f},
    };

    sg_begin_pass(&mrt_state.offscreen.pass);
    sg_apply_pipeline(mrt_state.offscreen.pip);
    sg_apply_bindings(&mrt_state.offscreen.bind);
    sg_apply_uniforms(mrt_UB_offscreen_params, &SG_RANGE(offscreen_params));
    sg_draw(0, 36, 1);
    sg_end_pass();

    sample_begin_pass(&mrt_state.display.pass_action, w, h);
    sg_apply_pipeline(mrt_state.display.pip);
    sg_apply_bindings(&mrt_state.display.bind);
    sg_apply_uniforms(mrt_UB_fsq_params, &SG_RANGE(fsq_params));
    sg_draw(0, 4, 1);
    sg_apply_pipeline(mrt_state.dbg.pip);
    for (int i = 0; i < MRT_NUM; i++)
    {
        sg_apply_viewport(i * 100, 0, 100, 100, false);
        mrt_state.dbg.bind.views[mrt_VIEW_tex] = mrt_state.display.bind.views[mrt_VIEW_tex0 + i];
        sg_apply_bindings(&mrt_state.dbg.bind);
        sg_draw(0, 4, 1);
    }
    sg_apply_viewport(0, 0, w, h, false);
    sg_end_pass();
    sg_commit();
}

static void mrt_shutdown(void)
{
    sg_destroy_pipeline(mrt_state.offscreen.pip);
    sg_destroy_pipeline(mrt_state.display.pip);
    sg_destroy_pipeline(mrt_state.dbg.pip);
    sg_destroy_buffer(mrt_state.offscreen.bind.vertex_buffers[0]);
    sg_destroy_buffer(mrt_state.offscreen.bind.index_buffer);
    sg_destroy_buffer(mrt_state.display.bind.vertex_buffers[0]);
    sg_destroy_sampler(mrt_state.display.bind.samplers[mrt_SMP_smp]);
    for (int i = 0; i < MRT_NUM; i++)
    {
        sg_destroy_image(mrt_state.images.color[i]);
        sg_destroy_view(mrt_state.offscreen.pass.attachments.colors[i]);
        sg_destroy_view(mrt_state.display.bind.views[mrt_VIEW_tex0 + i]);
    }
    sg_destroy_image(mrt_state.images.depth);
    sg_destroy_view(mrt_state.images.depth_view);
}

// ---------------------------------------------------------------- blend
#define BLEND_NUM_FACTORS (15)

static struct {
    sg_pass_action pass_action;
    sg_bindings bind;
    sg_pipeline pips[BLEND_NUM_FACTORS][BLEND_NUM_FACTORS];
    sg_pipeline bg_pip;
    float r;
    blend_quad_vs_params_t quad_vs_params;
    blend_bg_fs_params_t bg_fs_params;
} blend_state;

static void blend_init(void)
{
    blend_state.pass_action = (sg_pass_action){
        .colors[0].load_action = SG_LOADACTION_DONTCARE,
    };
    float vertices[] = {
        -1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.5f,
        1.0f, -1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.5f,
        -1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.5f,
        1.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.5f,
    };
    blend_state.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(vertices),
        .label = "blend-quad-vertices",
    });
    blend_state.bg_pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout = {
            .buffers[0].stride = 28,
            .attrs = {
                [blend_ATTR_bg_position].format = SG_VERTEXFORMAT_FLOAT2,
            },
        },
        .shader = sg_make_shader(blend_bg_shader_desc(sg_query_backend())),
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP,
        .label = "blend-bg-pipeline",
    });
    sg_pipeline_desc pip_desc = {
        .layout = {
            .attrs = {
                [blend_ATTR_quad_position].format = SG_VERTEXFORMAT_FLOAT3,
                [blend_ATTR_quad_color0].format = SG_VERTEXFORMAT_FLOAT4,
            },
        },
        .shader = sg_make_shader(blend_quad_shader_desc(sg_query_backend())),
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP,
        .blend_color = {1.0f, 0.0f, 0.0f, 1.0f},
        .label = "blend-pipeline",
    };
    for (int src = 0; src < BLEND_NUM_FACTORS; src++)
    {
        for (int dst = 0; dst < BLEND_NUM_FACTORS; dst++)
        {
            const sg_blend_factor src_blend = (sg_blend_factor)(src + 1);
            const sg_blend_factor dst_blend = (sg_blend_factor)(dst + 1);
            if ((src_blend == SG_BLENDFACTOR_BLEND_COLOR) || (src_blend == SG_BLENDFACTOR_ONE_MINUS_BLEND_COLOR))
            {
                if ((dst_blend == SG_BLENDFACTOR_BLEND_ALPHA) || (dst_blend == SG_BLENDFACTOR_ONE_MINUS_BLEND_ALPHA))
                {
                    continue;
                }
            }
            else if ((src_blend == SG_BLENDFACTOR_BLEND_ALPHA) || (src_blend == SG_BLENDFACTOR_ONE_MINUS_BLEND_ALPHA))
            {
                if ((dst_blend == SG_BLENDFACTOR_BLEND_COLOR) || (dst_blend == SG_BLENDFACTOR_ONE_MINUS_BLEND_COLOR))
                {
                    continue;
                }
            }
            pip_desc.colors[0].blend = (sg_blend_state){
                .enabled = true,
                .src_factor_rgb = src_blend,
                .dst_factor_rgb = dst_blend,
                .src_factor_alpha = SG_BLENDFACTOR_ONE,
                .dst_factor_alpha = SG_BLENDFACTOR_ZERO,
            };
            blend_state.pips[src][dst] = sg_make_pipeline(&pip_desc);
        }
    }
}

static void blend_frame(int w, int h)
{
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(90.0f), (float)w / (float)h, 0.01f, 100.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 0.0f, 20.0f), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    sample_begin_pass(&blend_state.pass_action, w, h);
    sg_apply_pipeline(blend_state.bg_pip);
    sg_apply_bindings(&blend_state.bind);
    sg_apply_uniforms(blend_UB_bg_fs_params, &SG_RANGE(blend_state.bg_fs_params));
    sg_draw(0, 4, 1);
    float r0 = blend_state.r;
    for (int src = 0; src < BLEND_NUM_FACTORS; src++)
    {
        for (int dst = 0; dst < BLEND_NUM_FACTORS; dst++, r0 += 0.6f)
        {
            if (blend_state.pips[src][dst].id == SG_INVALID_ID)
            {
                continue;
            }
            const mat44_t rm = mat44_rotation_y(vm_radians(r0));
            const float x = ((float)(dst - BLEND_NUM_FACTORS / 2)) * 3.0f;
            const float y = ((float)(src - BLEND_NUM_FACTORS / 2)) * 2.2f;
            const mat44_t model_trans = mat44_translation(x, y, 0.0f);
            const mat44_t model = vm_mul(rm, model_trans);
            blend_state.quad_vs_params.mvp = vm_mul(model, view_proj);
            sg_apply_pipeline(blend_state.pips[src][dst]);
            sg_apply_bindings(&blend_state.bind);
            sg_apply_uniforms(blend_UB_quad_vs_params, &SG_RANGE(blend_state.quad_vs_params));
            sg_draw(0, 4, 1);
        }
    }
    sg_end_pass();
    sg_commit();
    const float t = shim_dt() * 60.0f;
    blend_state.r += 0.6f * t;
    blend_state.bg_fs_params.tick += 1.0f * t;
}

static void blend_shutdown(void)
{
    for (int src = 0; src < BLEND_NUM_FACTORS; src++)
    {
        for (int dst = 0; dst < BLEND_NUM_FACTORS; dst++)
        {
            if (blend_state.pips[src][dst].id != SG_INVALID_ID)
            {
                sg_destroy_pipeline(blend_state.pips[src][dst]);
            }
        }
    }
    sg_destroy_pipeline(blend_state.bg_pip);
    sg_destroy_buffer(blend_state.bind.vertex_buffers[0]);
}

// ---------------------------------------------------------------- shapes
typedef struct {
    vec3_t pos;
    sshape_element_range_t draw;
} sshape_sample_shape_t;

enum {
    SHAPE_BOX = 0,
    SHAPE_PLANE,
    SHAPE_SPHERE,
    SHAPE_CYLINDER,
    SHAPE_TORUS,
    SHAPE_NUM
};

static struct {
    sg_pass_action pass_action;
    sg_pipeline pip;
    sg_buffer vbuf;
    sg_buffer ibuf;
    sshape_sample_shape_t shapes[SHAPE_NUM];
    shapes_vs_params_t vs_params;
    float rx, ry;
} shapes_state;

static void shapes_init(void)
{
    sdtx_setup(&(sdtx_desc_t){
        .fonts[0] = sdtx_font_oric(),
    });
    shapes_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.0f, 1.0f}},
    };
    shapes_state.shapes[SHAPE_BOX].pos = vec3(-1.0f, 1.0f, 0.0f);
    shapes_state.shapes[SHAPE_PLANE].pos = vec3(1.0f, 1.0f, 0.0f);
    shapes_state.shapes[SHAPE_SPHERE].pos = vec3(-2.0f, -1.0f, 0.0f);
    shapes_state.shapes[SHAPE_CYLINDER].pos = vec3(2.0f, -1.0f, 0.0f);
    shapes_state.shapes[SHAPE_TORUS].pos = vec3(0.0f, -1.0f, 0.0f);
    static uint8_t vertices[SSHAPE_MAX_VERTEX_SIZE * 6 * 1024];
    static uint16_t indices[16 * 1024];
    sshape_state_t shp = {
        .vertices.buffer = SSHAPE_RANGE(vertices),
        .indices.buffer = SSHAPE_RANGE(indices),
    };
    sshape_build_box(&shp, &(sshape_box_t){
        .width = 1.0f, .height = 1.0f, .depth = 1.0f, .tiles = 10, .random_colors = true,
    });
    shapes_state.shapes[SHAPE_BOX].draw = sshape_element_range(&shp);
    sshape_build_plane(&shp, &(sshape_plane_t){
        .width = 1.0f, .depth = 1.0f, .tiles = 10, .random_colors = true,
    });
    shapes_state.shapes[SHAPE_PLANE].draw = sshape_element_range(&shp);
    sshape_build_sphere(&shp, &(sshape_sphere_t){
        .radius = 0.75f, .slices = 36, .stacks = 20, .random_colors = true,
    });
    shapes_state.shapes[SHAPE_SPHERE].draw = sshape_element_range(&shp);
    sshape_build_cylinder(&shp, &(sshape_cylinder_t){
        .radius = 0.5f, .height = 1.5f, .slices = 36, .stacks = 10, .random_colors = true,
    });
    shapes_state.shapes[SHAPE_CYLINDER].draw = sshape_element_range(&shp);
    sshape_build_torus(&shp, &(sshape_torus_t){
        .radius = 0.5f, .ring_radius = 0.3f, .rings = 36, .sides = 18, .random_colors = true,
    });
    shapes_state.shapes[SHAPE_TORUS].draw = sshape_element_range(&shp);
    assert(shp.valid);
    const sg_buffer_desc vbuf_desc = sshape_vertex_buffer_desc(&shp);
    const sg_buffer_desc ibuf_desc = sshape_index_buffer_desc(&shp);
    shapes_state.vbuf = sg_make_buffer(&vbuf_desc);
    shapes_state.ibuf = sg_make_buffer(&ibuf_desc);
    shapes_state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = sg_make_shader(shapes_shapes_shader_desc(sg_query_backend())),
        .layout = {
            .buffers[0] = sshape_vertex_buffer_layout_state(&shp),
            .attrs = {
                [0] = sshape_position_vertex_attr_state(&shp),
                [1] = sshape_normal_vertex_attr_state(&shp),
                [2] = sshape_texcoord_vertex_attr_state(&shp),
                [3] = sshape_color_vertex_attr_state(&shp),
            },
        },
        .index_type = SG_INDEXTYPE_UINT16,
        .cull_mode = SG_CULLMODE_NONE,
        .depth = {.compare = SG_COMPAREFUNC_LESS_EQUAL, .write_enabled = true},
        .label = "shapes-pipeline",
    });
}

static void shapes_frame(int w, int h)
{
    const mat44_t proj = mat44_perspective_fov_rh(vm_radians(60.0f), (float)w / (float)h, 0.01f, 10.0f);
    const mat44_t view = mat44_look_at_rh(vec3(0.0f, 1.5f, 4.0f), vec3(0.0f, 0.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f));
    const mat44_t view_proj = vm_mul(view, proj);
    const float t = shim_dt() * 60.0f;
    shapes_state.rx += 1.0f * t;
    shapes_state.ry += 2.0f * t;
    const mat44_t rxm = mat44_rotation_x(vm_radians(shapes_state.rx));
    const mat44_t rym = mat44_rotation_y(vm_radians(shapes_state.ry));
    const mat44_t rm = vm_mul(rym, rxm);
    sample_begin_pass(&shapes_state.pass_action, w, h);
    sg_apply_pipeline(shapes_state.pip);
    sg_apply_bindings(&(sg_bindings){
        .vertex_buffers[0] = shapes_state.vbuf,
        .index_buffer = shapes_state.ibuf,
    });
    for (int i = 0; i < SHAPE_NUM; i++)
    {
        const mat44_t trans = mat44_translation(shapes_state.shapes[i].pos.x, shapes_state.shapes[i].pos.y, shapes_state.shapes[i].pos.z);
        const mat44_t model = vm_mul(rm, trans);
        shapes_state.vs_params.mvp = vm_mul(model, view_proj);
        sg_apply_uniforms(shapes_UB_vs_params, &SG_RANGE(shapes_state.vs_params));
        sg_draw(shapes_state.shapes[i].draw.base_element, shapes_state.shapes[i].draw.num_elements, 1);
    }
    sg_end_pass();
    sg_commit();
}

static void shapes_shutdown(void)
{
    sdtx_shutdown();
    sg_destroy_pipeline(shapes_state.pip);
    sg_destroy_buffer(shapes_state.vbuf);
    sg_destroy_buffer(shapes_state.ibuf);
}

// ---------------------------------------------------------------- sgl
static struct {
    sg_pass_action pass_action;
    sg_view tex_view;
    sg_sampler smp;
    sgl_pipeline pip_3d;
} sgl_state;

static void sgl_cube(void)
{
    sgl_begin_quads();
    sgl_c3f(1.0f, 0.0f, 0.0f);
    sgl_v3f_t2f(-1.0f, 1.0f, -1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, -1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, -1.0f, -1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, -1.0f, -1.0f, -1.0f);
    sgl_c3f(0.0f, 1.0f, 0.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, 1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, -1.0f, 1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, 1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(-1.0f, 1.0f, 1.0f, -1.0f, -1.0f);
    sgl_c3f(0.0f, 0.0f, 1.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, 1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(-1.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(-1.0f, 1.0f, -1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, -1.0f, -1.0f, -1.0f);
    sgl_c3f(1.0f, 0.5f, 0.0f);
    sgl_v3f_t2f(1.0f, -1.0f, 1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, -1.0f, -1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, -1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, 1.0f, -1.0f, -1.0f);
    sgl_c3f(0.0f, 0.5f, 1.0f);
    sgl_v3f_t2f(1.0f, -1.0f, -1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, -1.0f, 1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, 1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(-1.0f, -1.0f, -1.0f, -1.0f, -1.0f);
    sgl_c3f(1.0f, 0.0f, 0.5f);
    sgl_v3f_t2f(-1.0f, 1.0f, -1.0f, -1.0f, 1.0f);
    sgl_v3f_t2f(-1.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, 1.0f, 1.0f, -1.0f);
    sgl_v3f_t2f(1.0f, 1.0f, -1.0f, 1.0f, -1.0f);
    sgl_end();
}

static void sgl_draw_triangle(void)
{
    sgl_defaults();
    sgl_begin_triangles();
    sgl_v2f_c3b(0.0f, 0.5f, 255, 0, 0);
    sgl_v2f_c3b(-0.5f, -0.5f, 0, 0, 255);
    sgl_v2f_c3b(0.5f, -0.5f, 0, 255, 0);
    sgl_end();
}

static void sgl_draw_quad(float t)
{
    static float angle_deg = 0.0f;
    const float scale = 1.0f + sinf(sgl_rad(angle_deg)) * 0.5f;
    angle_deg += 1.0f * t;
    sgl_defaults();
    sgl_rotate(sgl_rad(angle_deg), 0.0f, 0.0f, 1.0f);
    sgl_scale(scale, scale, 1.0f);
    sgl_begin_quads();
    sgl_v2f_c3b(-0.5f, -0.5f, 255, 255, 0);
    sgl_v2f_c3b(0.5f, -0.5f, 0, 255, 0);
    sgl_v2f_c3b(0.5f, 0.5f, 0, 0, 255);
    sgl_v2f_c3b(-0.5f, 0.5f, 255, 0, 0);
    sgl_end();
}

static void sgl_draw_cubes(const float t)
{
    static float rot[2] = {0.0f, 0.0f};
    rot[0] += 1.0f * t;
    rot[1] += 2.0f * t;
    sgl_defaults();
    sgl_load_pipeline(sgl_state.pip_3d);
    sgl_matrix_mode_projection();
    sgl_perspective(sgl_rad(45.0f), 1.0f, 0.1f, 100.0f);
    sgl_matrix_mode_modelview();
    sgl_translate(0.0f, 0.0f, -12.0f);
    sgl_rotate(sgl_rad(rot[0]), 1.0f, 0.0f, 0.0f);
    sgl_rotate(sgl_rad(rot[1]), 0.0f, 1.0f, 0.0f);
    sgl_cube();
    sgl_push_matrix();
    sgl_translate(0.0f, 0.0f, 3.0f);
    sgl_scale(0.5f, 0.5f, 0.5f);
    sgl_rotate(-2.0f * sgl_rad(rot[0]), 1.0f, 0.0f, 0.0f);
    sgl_rotate(-2.0f * sgl_rad(rot[1]), 0.0f, 1.0f, 0.0f);
    sgl_cube();
    sgl_push_matrix();
    sgl_translate(0.0f, 0.0f, 3.0f);
    sgl_scale(0.5f, 0.5f, 0.5f);
    sgl_rotate(-3.0f * sgl_rad(2 * rot[0]), 1.0f, 0.0f, 0.0f);
    sgl_rotate(3.0f * sgl_rad(2 * rot[1]), 0.0f, 0.0f, 1.0f);
    sgl_cube();
    sgl_pop_matrix();
    sgl_pop_matrix();
}

static void sgl_draw_tex_cube(const float t)
{
    static float frame_count = 0.0f;
    frame_count += 1.0f * t;
    const float a = sgl_rad(frame_count);
    const float tex_rot = 0.5f * a;
    const float tex_scale = 1.0f + sinf(a) * 0.5f;
    const float eye_x = sinf(a) * 6.0f;
    const float eye_z = cosf(a) * 6.0f;
    const float eye_y = sinf(a) * 3.0f;
    sgl_defaults();
    sgl_load_pipeline(sgl_state.pip_3d);
    sgl_enable_texture();
    sgl_texture(sgl_state.tex_view, sgl_state.smp);
    sgl_matrix_mode_projection();
    sgl_perspective(sgl_rad(45.0f), 1.0f, 0.1f, 100.0f);
    sgl_matrix_mode_modelview();
    sgl_lookat(eye_x, eye_y, eye_z, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f);
    sgl_matrix_mode_texture();
    sgl_rotate(tex_rot, 0.0f, 0.0f, 1.0f);
    sgl_scale(tex_scale, tex_scale, 1.0f);
    sgl_cube();
}

static void sgl_sample_init(void)
{
    sgl_setup(&(sgl_desc_t){0});
    uint32_t pixels[8][8];
    for (int y = 0; y < 8; y++)
    {
        for (int x = 0; x < 8; x++)
        {
            pixels[y][x] = ((y ^ x) & 1) ? 0xFFFFFFFF : 0xFF000000;
        }
    }
    sgl_state.tex_view = sg_make_view(&(sg_view_desc){
        .texture = {
            .image = sg_make_image(&(sg_image_desc){
                .width = 8,
                .height = 8,
                .data = SG_RANGE(pixels),
                .label = "sgl-checkerboard",
            }),
        },
        .label = "sgl-tex-view",
    });
    sgl_state.smp = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_NEAREST,
        .mag_filter = SG_FILTER_NEAREST,
        .label = "sgl-sampler",
    });
    sgl_state.pip_3d = sgl_make_pipeline(&(sg_pipeline_desc){
        .cull_mode = SG_CULLMODE_BACK,
        .depth = {.write_enabled = true, .compare = SG_COMPAREFUNC_LESS_EQUAL},
        .label = "sgl-pip-3d",
    });
    sgl_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.0f, 0.0f, 1.0f}},
    };
}

static void sgl_sample_frame(int w, int h)
{
    const float t = shim_dt() * 60.0f;
    const int dw = w;
    const int dh = h;
    const int ww = dh / 2;
    const int hh = dh / 2;
    const int x0 = dw / 2 - hh;
    const int x1 = dw / 2;
    const int y0 = 0;
    const int y1 = dh / 2;
    sgl_viewport(x0, y0, ww, hh, true);
    sgl_draw_triangle();
    sgl_viewport(x1, y0, ww, hh, true);
    sgl_draw_quad(t);
    sgl_viewport(x0, y1, ww, hh, true);
    sgl_draw_cubes(t);
    sgl_viewport(x1, y1, ww, hh, true);
    sgl_draw_tex_cube(t);
    sgl_viewport(0, 0, dw, dh, true);
    sample_begin_pass(&sgl_state.pass_action, w, h);
    sgl_draw();
    sg_end_pass();
    sg_commit();
}

static void sgl_sample_shutdown(void)
{
    sgl_destroy_pipeline(sgl_state.pip_3d);
    sg_destroy_view(sgl_state.tex_view);
    sg_destroy_sampler(sgl_state.smp);
    sgl_shutdown();
}

// ---------------------------------------------------------------- debugtext
#define FONT_KC853 (0)
#define FONT_KC854 (1)
#define FONT_Z1013 (2)
#define FONT_CPC (3)
#define FONT_C64 (4)
#define FONT_ORIC (5)

static struct {
    sg_pass_action pass_action;
} sdtx_state;

static void debugtext_init(void)
{
    sdtx_setup(&(sdtx_desc_t){
        .fonts = {
            [FONT_KC853] = sdtx_font_kc853(),
            [FONT_KC854] = sdtx_font_kc854(),
            [FONT_Z1013] = sdtx_font_z1013(),
            [FONT_CPC] = sdtx_font_cpc(),
            [FONT_C64] = sdtx_font_c64(),
            [FONT_ORIC] = sdtx_font_oric(),
        },
    });
    sdtx_state.pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.0f, 0.125f, 0.25f, 1.0f}},
    };
}

static void debugtext_print_font(int font_index, const char *title, uint8_t r, uint8_t g, uint8_t b)
{
    sdtx_font(font_index);
    sdtx_color3b(r, g, b);
    sdtx_puts(title);
    for (int c = 32; c < 256; c++)
    {
        sdtx_putc((char)c);
        if (((c + 1) & 63) == 0)
        {
            sdtx_crlf();
        }
    }
    sdtx_crlf();
}

static void debugtext_frame(int w, int h)
{
    sdtx_canvas((float)w * 0.5f, (float)h * 0.5f);
    sdtx_origin(0.0f, 2.0f);
    sdtx_home();
    debugtext_print_font(FONT_KC853, "KC85/3:\n", 0xf4, 0x43, 0x36);
    debugtext_print_font(FONT_KC854, "KC85/4:\n", 0x21, 0x96, 0xf3);
    debugtext_print_font(FONT_Z1013, "Z1013:\n", 0x4c, 0xaf, 0x50);
    debugtext_print_font(FONT_CPC, "Amstrad CPC:\n", 0xff, 0xeb, 0x3b);
    debugtext_print_font(FONT_C64, "C64:\n", 0x79, 0x86, 0xcb);
    debugtext_print_font(FONT_ORIC, "Oric Atmos:\n", 0xff, 0x98, 0x00);
    sample_begin_pass(&sdtx_state.pass_action, w, h);
    sdtx_draw();
    sg_end_pass();
    sg_commit();
}

static void debugtext_shutdown(void)
{
    sdtx_shutdown();
}

// ---------------------------------------------------------------- registry
// index 0 = triangle demo (shim path); sample_frame(0) is never reached
static const sample_t samples_table[] = {
    {"triangle", NULL, NULL, NULL, NULL},
    {"quad", quad_init, quad_frame, quad_shutdown, NULL},
    {"mandelbrot", mandelbrot_init, mandelbrot_frame, mandelbrot_shutdown, NULL},
    {"cube", cube_init, cube_frame, cube_shutdown, NULL},
    {"instancing", instancing_init, instancing_frame, instancing_shutdown, NULL},
    {"offscreen", offscreen_init, offscreen_frame, offscreen_shutdown, NULL},
    {"dyntex", dyntex_init, dyntex_frame, dyntex_shutdown, NULL},
    {"mrt", mrt_init, mrt_frame, mrt_shutdown, NULL},
    {"blend", blend_init, blend_frame, blend_shutdown, NULL},
    {"shapes", shapes_init, shapes_frame, shapes_shutdown, NULL},
    {"sgl", sgl_sample_init, sgl_sample_frame, sgl_sample_shutdown, NULL},
    {"debugtext", debugtext_init, debugtext_frame, debugtext_shutdown, NULL},
};

int sample_count(void)
{
    return (int)(sizeof(samples_table) / sizeof(samples_table[0]));
}

const sample_t *sample_get(int index)
{
    if (index < 0 || index >= sample_count())
    {
        return NULL;
    }
    return &samples_table[index];
}

void sample_init(int index)
{
    const sample_t *s = sample_get(index);
    if (s && s->init)
    {
        s->init();
    }
}

void sample_frame(int index, int width, int height)
{
    const sample_t *s = sample_get(index);
    if (s && s->frame)
    {
        s->frame(width, height);
    }
}

void sample_shutdown(int index)
{
    const sample_t *s = sample_get(index);
    if (s && s->shutdown)
    {
        s->shutdown();
    }
}

bool sample_verify(int index, const unsigned char pixels[16])
{
    const sample_t *s = sample_get(index);
    if (s && s->verify)
    {
        return s->verify(pixels);
    }
    return true;
}
