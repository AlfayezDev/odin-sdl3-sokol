#pragma once
#include <stdbool.h>
#include <stdint.h>

// Dependency-free ports of floooh/sokol-samples to the shim platform layer.
// Each sample owns its sokol-gfx resources and drives the whole frame
// (begin pass, draw, end pass, commit); the Odin side only selects one.

typedef struct {
    const char *name;
    void (*init)(void);
    void (*frame)(int width, int height);
    void (*shutdown)(void);
    bool (*verify)(const unsigned char pixels[16]); // optional pixel check
} sample_t;

const sample_t *sample_get(int index);
int sample_count(void);

// flat entry points for the Odin bindings
void sample_init(int index);
void sample_frame(int index, int width, int height);
void sample_shutdown(int index);
bool sample_verify(int index, const unsigned char pixels[16]);
