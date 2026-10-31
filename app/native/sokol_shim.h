#pragma once
#include <stdbool.h>
#include <stdint.h>

// Flat C API over sokol_gfx for the Odin side. Owns all sokol API-surface
// complexity (descriptors, passes, pipelines); Odin binds only these.

void shim_init(void);
void shim_shutdown(void);
void shim_begin_frame(int width, int height);
void shim_compute(void);        // dispatch: fills the storage buffer [11,14,17,20]
void shim_render(void);         // fullscreen pass; fragment encodes vals in alpha
bool shim_read_pixels(unsigned char out[16]); // read 4 RGBA pixels (band centers)
bool shim_read_storage(unsigned char out[16]); // test harness: glGetBufferSubData
void shim_end_frame(void);      // end pass + commit (caller swaps)
