#pragma once
#include <stdbool.h>
#include <stdint.h>

// Flat C API over sokol_gfx for the Odin side. Owns all sokol API-surface
// complexity plus the platform setup: SDL's GL context (desktop GL 4.1 core
// or Android ES 3.0) is requested via shim_gl_attributes and created by SDL.

void shim_gl_attributes(void); // per-platform SDL GL context attributes
void shim_init(void *sdl_window);
void shim_shutdown(void);
void shim_begin_default_pass(int width, int height);
void shim_render(void);                        // the classic color triangle
bool shim_read_pixels(unsigned char out[16]);  // 4 RGBA samples (3 vertices + center)
void shim_end_frame(void);
void shim_swap(void);                          // present
