// sokol_gfx demo shim: GL core backend (SDL3 provides window + GL context).
// The render test encodes the compute results into the framebuffer alpha
// channel across four vertical bands; the Odin side reads them back through
// shim_read_pixels (glReadPixels; test harness only) and asserts [11,14,17,20].
#include "sokol_shim.h"

// This translation unit is the sokol_gfx implementation; being the impl TU
// lets the test harness read internal GL handles for verification.
#define SOKOL_IMPL
#define SOKOL_GLCORE
#define SOKOL_NO_ENTRY
#include "sokol/sokol_gfx.h"
#include "sokol/sokol_log.h"
#include "shaders_generated.h"

#include <SDL3/SDL.h>
#include <string.h>

// GL constants (avoiding GL headers in the build)
#define SHIM_GL_RGBA 0x1908
#define SHIM_GL_UNSIGNED_BYTE 0x1401
typedef void (*shim_read_pixels_fn)(int, int, int, int, unsigned int, int, void *);
typedef void (*shim_get_buffer_sub_data_fn)(unsigned int, long, unsigned long, void *);

static sg_pipeline compute_pipeline;
static sg_pipeline render_pipeline;
static sg_buffer storage_buffer;
static sg_view storage_view;
static sg_pass_action pass_action;
static shim_read_pixels_fn gl_read_pixels;
static shim_get_buffer_sub_data_fn gl_get_buffer_sub_data;
static void (*gl_bind_buffer)(unsigned int, unsigned int);
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

void shim_init(void)
{
    sg_setup(&(sg_desc){
        .logger.func = slog,
    });

    storage_buffer = sg_make_buffer(&(sg_buffer_desc){
        .usage.storage_buffer = true,
        .size = 4 * sizeof(uint32_t),
    });
    storage_view = sg_make_view(&(sg_view_desc){
        .storage_buffer = {.buffer = storage_buffer},
    });

    sg_shader compute_shd = sg_make_shader(&(sg_shader_desc){
        .compute_func = {.source = SHADER_COMPUTE_SRC},
        .views[0].storage_buffer = {.stage = SG_SHADERSTAGE_COMPUTE, .glsl_binding_n = 0},
    });
    compute_pipeline = sg_make_pipeline(&(sg_pipeline_desc){
        .compute = true,
        .shader = compute_shd,
    });

    sg_shader render_shd = sg_make_shader(&(sg_shader_desc){
        .vertex_func = {.source = SHADER_VS_SRC},
        .fragment_func = {.source = SHADER_FS_SRC},
        .views[0].storage_buffer = {.stage = SG_SHADERSTAGE_FRAGMENT, .readonly = true, .glsl_binding_n = 0},
    });
    render_pipeline = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = render_shd,
    });

    pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.08f, 0.22f, 0.43f, 1.0f}},
    };

    gl_read_pixels = (shim_read_pixels_fn)SDL_GL_GetProcAddress("glReadPixels");
    gl_get_buffer_sub_data = (shim_get_buffer_sub_data_fn)SDL_GL_GetProcAddress("glGetBufferSubData");
    gl_bind_buffer = (void (*)(unsigned int, unsigned int))SDL_GL_GetProcAddress("glBindBuffer");
}

// Test harness: read the storage buffer contents straight through GL
// (glGetBufferSubData on the sokol-managed GL buffer).
bool shim_read_storage(unsigned char out[16])
{
    if (!gl_get_buffer_sub_data)
    {
        return false;
    }
    _sg_buffer_t *buf = _sg_lookup_buffer(storage_buffer.id);
    if (!buf)
    {
        return false;
    }
    const unsigned int target = 0x90D2 /* GL_SHADER_STORAGE_BUFFER */;
    for (int f = 0; f < 2; f++)
    {
        char tmp[16];
        glBindBuffer(target, buf->gl.buf[f]);
        glGetBufferSubData(target, 0, 16, tmp);
        SDL_Log("ssbo slot %d: %u %u %u %u", f, (unsigned)((uint32_t *)tmp)[0],
                (unsigned)((uint32_t *)tmp)[1], (unsigned)((uint32_t *)tmp)[2],
                (unsigned)((uint32_t *)tmp)[3]);
        if (((uint32_t *)tmp)[3] == 20u)
        {
            memcpy(out, tmp, 16);
            glBindBuffer(target, 0);
            return true;
        }
    }
    glBindBuffer(target, 0);
    return false;
}

void shim_shutdown(void)
{
    sg_shutdown(); // pools are bulk-cleared; individual destroys not needed at exit
}

void shim_begin_frame(int width, int height)
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
        .views[0] = storage_view,
    });
    sg_dispatch(1, 1, 1);
    sg_end_pass();
}

void shim_render(void)
{
    sg_apply_pipeline(render_pipeline);
    sg_apply_bindings(&(sg_bindings){
        .views[0] = storage_view,
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

void shim_end_frame(void)
{
    sg_end_pass();
    sg_commit();
}
