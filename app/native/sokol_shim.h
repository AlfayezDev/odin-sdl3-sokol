#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <SDL3/SDL_platform_defines.h>

// Backend selection shared by every sokol translation unit: GLES 3.0 on
// Android/iOS, desktop GL 4.1 core elsewhere. Generated shader headers key
// off the same macros.
#if defined(__ANDROID__) || defined(__IPHONEOS__)
#define SHIM_GLES3
#else
#define SHIM_GLCORE
#endif

// Flat C API over sokol_gfx for the Odin side. Owns the sokol_gfx impl plus
// the platform setup: SDL's GL context (desktop GL 4.1 core or Android/iOS
// ES 3.0) is requested via shim_gl_attributes and created by SDL.

void shim_gl_attributes(void); // per-platform SDL GL context attributes
void shim_init(void *sdl_window);
void shim_shutdown(void);

// frame timing for the sample harness
void shim_frame_begin(void);
float shim_dt(void);
float shim_time(void);

// triangle demo (sample 0) + its pixel-readback verification
void shim_begin_default_pass(int width, int height);
void shim_render(void);
bool shim_read_pixels(unsigned char out[16]);  // 4 RGBA samples (3 vertices + center)
void shim_end_frame(void);

void shim_swap(void);                          // present
