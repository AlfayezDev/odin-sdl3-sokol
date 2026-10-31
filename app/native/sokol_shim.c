// sokol_gfx demo shim: GL core (GLSL 410) on desktop, GLES3 (GLSL 300 es) on
// Android. SDL3 provides the window; this shim owns the GL/EGL context setup,
// sokol_gfx, and the swap. The render test draws the classic three-vertex
// color triangle; the Odin side verifies the interpolated vertex colors via
// glReadPixels at the corners and centroid.
#include "sokol_shim.h"

// sokol_gfx implementation TU (GL core on desktop, GLES3 on Android).
#define SOKOL_IMPL
#if defined(__ANDROID__)
#define SOKOL_GLES3
#else
#define SOKOL_GLCORE
#endif
#define SOKOL_NO_ENTRY
#include "sokol/sokol_gfx.h"
#include "sokol/sokol_log.h"

#ifdef SOKOL_GLES3
#include "triangle_gles300.h"
#define TRIANGLE_SHADER_DESC triangle_gles300_shader_desc
#else
#include "triangle_gl330.h"
#define TRIANGLE_SHADER_DESC triangle_gl330_shader_desc
#endif

#include <SDL3/SDL.h>
#include <string.h>

// GL constants (avoiding GL headers in the build)
#define SHIM_GL_RGBA 0x1908
#define SHIM_GL_UNSIGNED_BYTE 0x1401
typedef void (*shim_read_pixels_fn)(int, int, int, int, unsigned int, int, void *);

static sg_pipeline pipeline;
static sg_buffer vertices;
static sg_pass_action pass_action;
static shim_read_pixels_fn gl_read_pixels;
static int frame_width, frame_height;
static void *sdl_window_handle;
static void *sdl_window_handle;

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

// The classic sokol triangle: positions + per-vertex colors.
static const float triangle_vertices[] = {
    // positions        colors
    0.0f, 0.5f, 0.5f,   1.0f, 0.0f, 0.0f,
    -0.5f, -0.5f, 0.5f, 0.0f, 1.0f, 0.0f,
    0.5f, -0.5f, 0.5f,  0.0f, 0.0f, 1.0f,
};

void shim_gl_attributes(void)
{
#if defined(__ANDROID__)
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#else
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
#endif
}

void shim_init(void *sdl_window)
{
    sdl_window_handle = sdl_window;

    sg_setup(&(sg_desc){
        .logger.func = slog,
    });

    vertices = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(triangle_vertices),
        .label = "triangle-vertices",
    });

    sg_shader shd = sg_make_shader(triangle_shader_desc(sg_query_backend()));
    pipeline = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = shd,
        .layout = {
            .attrs = {
                [0].format = SG_VERTEXFORMAT_FLOAT3,
                [1].format = SG_VERTEXFORMAT_FLOAT3,
            },
        },
        .label = "triangle-pipeline",
    });

    pass_action = (sg_pass_action){
        .colors[0] = {.load_action = SG_LOADACTION_CLEAR, .clear_value = {0.08f, 0.22f, 0.43f, 1.0f}},
    };

    gl_read_pixels = (shim_read_pixels_fn)SDL_GL_GetProcAddress("glReadPixels");
}

void shim_shutdown(void)
{
    sg_destroy_pipeline(pipeline);
    sg_destroy_buffer(vertices);
    sg_shutdown();
}

void shim_begin_default_pass(int width, int height)
{
    frame_width = width;
    frame_height = height;
    sg_begin_pass(&(sg_pass){
        .swapchain = {.width = width, .height = height},
        .action = pass_action,
    });
}

void shim_render(void)
{
    sg_apply_pipeline(pipeline);
    sg_apply_bindings(&(sg_bindings){
        .vertex_buffers[0] = vertices,
    });
    sg_draw(0, 3, 1);
}

// Reads four RGBA pixels: the three vertex corners (in screen space) plus the
// triangle centroid. glReadPixels must run before the swap.
bool shim_read_pixels(unsigned char out[16])
{
    if (!gl_read_pixels || frame_width <= 0)
    {
        return false;
    }
    // sample points: the three vertices nudged 1% toward the centroid (so the
    // pixel lands strictly inside the triangle) plus the centroid itself
    const float nx[4] = {0.0f, -0.495f, 0.495f, 0.0f};
    const float ny[4] = {0.495f, -0.495f, -0.495f, 0.0f};
    for (int i = 0; i < 4; i++)
    {
        // glReadPixels row 0 is the framebuffer bottom (GL convention): map
        // NDC [-1,1] directly, no extra flip
        const int x = (int)((nx[i] * 0.5f + 0.5f) * (float)frame_width);
        const int y = (int)((ny[i] * 0.5f + 0.5f) * (float)frame_height);
        gl_read_pixels(x, y, 1, 1, SHIM_GL_RGBA, SHIM_GL_UNSIGNED_BYTE, &out[i * 4]);
    }
    return true;
}

void shim_end_frame(void)
{
    sg_end_pass();
    sg_commit();
}

void shim_swap(void)
{
    SDL_GL_SwapWindow((SDL_Window *)sdl_window_handle);
}
