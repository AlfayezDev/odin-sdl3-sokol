// sokol_gfx demo shim: GL core on desktop, GLES3 on Android (SDL3 provides
// the window + GL context). The render test encodes the compute results into
// the framebuffer alpha channel across four vertical bands; the Odin side
// reads them back through shim_read_pixels and asserts [11,14,17,20].
#include "sokol_shim.h"

// This translation unit is the sokol_gfx implementation; being the impl TU
// lets the test harness read internal GL handles for verification.
// GL core on desktop, GLES3 on Android (compute/SSBO need GLES 3.1+).
#define SOKOL_IMPL
#if defined(__ANDROID__)
#define SOKOL_GLES3
#else
#define SOKOL_GLCORE
#endif
#define SOKOL_NO_ENTRY
#include "sokol/sokol_gfx.h"
#include "sokol/sokol_log.h"
#include "shaders_generated.h"

#ifdef SOKOL_GLES3
#define SHADER_VS_SRC       SHADER_VS_SRC_GLES
#define SHADER_FS_SRC       SHADER_FS_SRC_GLES
#define SHADER_COMPUTE_SRC  SHADER_COMPUTE_SRC_GLES
#endif

#include <SDL3/SDL.h>
#include <string.h>

// GL constants (avoiding GL headers in the build)
#define SHIM_GL_RGBA 0x1908
#define SHIM_GL_UNSIGNED_BYTE 0x1401
typedef void (*shim_read_pixels_fn)(int, int, int, int, unsigned int, int, void *);
#ifndef SOKOL_GLES3
typedef void (*shim_get_buffer_sub_data_fn)(unsigned int, long, unsigned long, void *);
#endif

static sg_pipeline compute_pipeline;
static sg_pipeline render_pipeline;
static sg_image result_image;
static sg_view result_view_storage;  // compute: storage image write
static sg_view result_view_sampled;  // render: sampled read
static sg_sampler result_sampler;
static sg_pass_action pass_action;
static shim_read_pixels_fn gl_read_pixels;
#ifndef SOKOL_GLES3
static shim_get_buffer_sub_data_fn gl_get_buffer_sub_data;
static void (*gl_bind_buffer)(unsigned int, unsigned int);
#endif
static int frame_width, frame_height;

static void slog(const char *tag, uint32_t log_level, uint32_t log_item, const char *message, uint32_t line_nr, const char *func_name, void *user_data)
{
    (void)tag;
    (void)log_level;
    (void)log_item;
    (void)line_nr;
    (void)func_name;
    (void)user_data;
    SDL_Log("%s", message);
}

#ifdef SOKOL_GLES3
// Mali diagnosis: replicate sokol's per-stage compiles and the vs+fs program
// link with the driver, surfacing the info-logs (sokol only logs the generic
// failure message).
static void shim_check_gles(void)
{
    unsigned int (*p_create)(unsigned int) = (unsigned int (*)(unsigned int))SDL_GL_GetProcAddress("glCreateShader");
    void (*p_source)(unsigned int, long, const char **, const int *) = (void (*)(unsigned int, long, const char **, const int *))SDL_GL_GetProcAddress("glShaderSource");
    void (*p_compile)(unsigned int) = (void (*)(unsigned int))SDL_GL_GetProcAddress("glCompileShader");
    void (*p_getiv)(unsigned int, unsigned int, int *, int *) = (void (*)(unsigned int, unsigned int, int *, int *))SDL_GL_GetProcAddress("glGetShaderiv");
    void (*p_getlog)(unsigned int, long, int *, char *) = (void (*)(unsigned int, long, int *, char *))SDL_GL_GetProcAddress("glGetShaderInfoLog");
    void (*p_del)(unsigned int) = (void (*)(unsigned int))SDL_GL_GetProcAddress("glDeleteShader");
    unsigned int (*p_prog)(void) = (unsigned int (*)(void))SDL_GL_GetProcAddress("glCreateProgram");
    void (*p_attach)(unsigned int, unsigned int) = (void (*)(unsigned int, unsigned int))SDL_GL_GetProcAddress("glAttachShader");
    void (*p_link)(unsigned int) = (void (*)(unsigned int))SDL_GL_GetProcAddress("glLinkProgram");
    void (*p_piv)(unsigned int, unsigned int, int *, int *) = (void (*)(unsigned int, unsigned int, int *, int *))SDL_GL_GetProcAddress("glGetProgramiv");
    void (*p_plog)(unsigned int, long, int *, char *) = (void (*)(unsigned int, long, int *, char *))SDL_GL_GetProcAddress("glGetProgramInfoLog");
    if (!p_create || !p_source || !p_compile || !p_getiv || !p_getlog || !p_del || !p_prog || !p_attach || !p_link || !p_piv || !p_plog)
    {
        return;
    }
    const char *sources[3] = {SHADER_VS_SRC_GLES, SHADER_FS_SRC_GLES, SHADER_COMPUTE_SRC_GLES};
    const char *names[3] = {"vertex", "fragment", "compute"};
    unsigned int stages[3] = {0x8B31, 0x8B30, 0x91B9};
    for (int i = 0; i < 3; i++)
    {
        unsigned int shd = p_create(stages[i]);
        const char *src = sources[i];
        int len = (int)strlen(src);
        p_source(shd, 1, &src, &len);
        p_compile(shd);
        int ok = 0;
        p_getiv(shd, 0x8B01 /* GL_COMPILE_STATUS */, &ok, NULL);
        if (!ok)
        {
            char logbuf[2048] = {0};
            int n = 0;
            p_getlog(shd, (int)sizeof(logbuf) - 1, &n, logbuf);
            SDL_Log("GLSL %s compile failed:\n%s", names[i], logbuf);
        }
        p_del(shd);
    }
    unsigned int vs = p_create(0x8B31);
    unsigned int fs = p_create(0x8B30);
    const char *vs_src = SHADER_VS_SRC_GLES;
    const char *fs_src = SHADER_FS_SRC_GLES;
    int vlen = (int)strlen(vs_src);
    int flen = (int)strlen(fs_src);
    p_source(vs, 1, &vs_src, &vlen);
    p_compile(vs);
    p_source(fs, 1, &fs_src, &flen);
    p_compile(fs);
    unsigned int prog = p_prog();
    p_attach(prog, vs);
    p_attach(prog, fs);
    p_link(prog);
    int linked = 0;
    p_piv(prog, 0x8B82 /* GL_LINK_STATUS */, &linked, NULL);
    if (!linked)
    {
        char logbuf[2048] = {0};
        int n = 0;
        p_plog(prog, (int)sizeof(logbuf) - 1, &n, logbuf);
        SDL_Log("GLSL program link failed:\n%s", logbuf);
    }
    p_del(vs);
    p_del(fs);
    p_del(prog);
}
#endif

void shim_init(void)
{
    sg_setup(&(sg_desc){
        .logger.func = slog,
    });

#ifdef SOKOL_GLES3
    shim_check_gles();
#endif

    result_image = sg_make_image(&(sg_image_desc){
        .width = 4,
        .height = 1,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage = {.storage_image = true},
    });
    result_view_storage = sg_make_view(&(sg_view_desc){
        .storage_image = {.image = result_image},
    });
    result_view_sampled = sg_make_view(&(sg_view_desc){
        .texture = {.image = result_image},
    });
    result_sampler = sg_make_sampler(&(sg_sampler_desc){});

    sg_shader compute_shd = sg_make_shader(&(sg_shader_desc){
        .compute_func = {.source = SHADER_COMPUTE_SRC},
        .views[0].storage_image = {.stage = SG_SHADERSTAGE_COMPUTE, .access_format = SG_PIXELFORMAT_RGBA8},
    });
    compute_pipeline = sg_make_pipeline(&(sg_pipeline_desc){
        .compute = true,
        .shader = compute_shd,
    });

    sg_shader render_shd = sg_make_shader(&(sg_shader_desc){
        .vertex_func = {.source = SHADER_VS_SRC},
        .fragment_func = {.source = SHADER_FS_SRC},
        .views[1].texture = {.stage = SG_SHADERSTAGE_FRAGMENT},
        .samplers[0] = {.stage = SG_SHADERSTAGE_FRAGMENT},
        .texture_sampler_pairs[0] = {.stage = SG_SHADERSTAGE_FRAGMENT, .view_slot = 1, .sampler_slot = 0},
    });
    render_pipeline = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = render_shd,
    });

    pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.08f, 0.22f, 0.43f, 1.0f}},
    };

    gl_read_pixels = (shim_read_pixels_fn)SDL_GL_GetProcAddress("glReadPixels");
#ifndef SOKOL_GLES3
    gl_get_buffer_sub_data = (shim_get_buffer_sub_data_fn)SDL_GL_GetProcAddress("glGetBufferSubData");
    gl_bind_buffer = (void (*)(unsigned int, unsigned int))SDL_GL_GetProcAddress("glBindBuffer");
#endif
}

void shim_shutdown(void)
{
    sg_shutdown(); // pools are bulk-cleared at exit
}

void shim_resize(int width, int height)
{
    frame_width = width;
    frame_height = height;
}

void shim_begin_default_pass(int width, int height)
{
    frame_width = width;
    frame_height = height;
    sg_begin_pass(&(sg_pass){
        .swapchain = {.width = width, .height = height},
    });
}

void shim_compute(void)
{
    sg_pass pass = {.compute = true};
    sg_begin_pass(&pass);
    sg_apply_pipeline(compute_pipeline);
    sg_apply_bindings(&(sg_bindings){
        .views[0] = result_view_storage,
    });
    sg_dispatch(1, 1, 1);
    sg_end_pass();
}

void shim_render(void)
{
    sg_apply_pipeline(render_pipeline);
    sg_apply_bindings(&(sg_bindings){
        .views[1] = result_view_sampled,
        .samplers[0] = result_sampler,
    });
    sg_draw(3, 1, 1);
}

// Reads four RGBA pixels centered in each vertical band. glReadPixels must
// run before the swap.
bool shim_read_pixels(unsigned char out[16])
{
    if (!gl_read_pixels || frame_width <= 0)
    {
        return false;
    }
    const int band = frame_width / 4;
    for (int i = 0; i < 4; i++)
    {
        const int x = band * i + band / 2;
        const int y = frame_height / 2;
        gl_read_pixels(x, y, 1, 1, SHIM_GL_RGBA, SHIM_GL_UNSIGNED_BYTE, &out[i * 4]);
    }
    return true;
}

// Test harness verification read. Desktop GL: glGetTexImage straight from
// the compute-written image texels. GLES (Android) has no texture readback —
// the render pass paints the compute results into the framebuffer, so
// glReadPixels verifies the same numbers through the visible render.
bool shim_read_storage(unsigned char out[16])
{
#ifdef SOKOL_GLES3
    return shim_read_pixels(out);
#else
    if (!gl_get_tex_image || !gl_bind_texture)
    {
        return false;
    }
    _sg_image_t *tex = _sg_lookup_image(result_image.id);
    if (!tex)
    {
        return false;
    }
    gl_bind_texture(0x0DE1 /* GL_TEXTURE_2D */, tex->gl.tex[0]);
    gl_get_tex_image(0x0DE1, 0, SHIM_GL_RGBA, SHIM_GL_UNSIGNED_BYTE, out);
    // normalize: the values travel in the alpha byte of each texel
    unsigned char a[4];
    for (int i = 0; i < 4; i++)
    {
        a[i] = out[i * 4 + 3];
    }
    memset(out, 0, 16);
    for (int i = 0; i < 4; i++)
    {
        out[i * 4] = a[i];
    }
    return true;
#endif
}

void shim_end_frame(void)
{
    sg_end_pass();
    sg_commit();
}
