# Odin + SDL3 + sokol_gfx

The same Odin demo as `odin-sdl3-mobile` on a sokol_gfx graphics stack:
SDL3 as the platform layer (window/input/context), sokol_gfx as the renderer
(GL core backend on desktop, GLES3 on mobile later).

- compute dispatch writes `[11, 14, 17, 20]` into a storage buffer
- the render pass reads the storage buffer and encodes the values into the
  framebuffer alpha channel, verified by readback asserts
- one Slang module (`shaders/app.slang`) → GLSL per sokol's GL backend,
  processed by `scripts/shaders.py`

```sh
./scripts/deps.sh            # fetch SDL3 (pinned)
odin run . -- desktop        # build + run
```

## Status

| Platform | Backend | Status |
|---|---|---|
| Linux desktop | GL core (SDL3) | ✅ |
| macOS / Windows | GL core (SDL3) | planned |
| Android | GLES3 (SDL3) | planned |
| iOS | GLES3/Metal (SDL3) | planned |
