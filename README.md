# Odin + SDL3 + sokol_gfx

One Odin app, 12 sokol_gfx demos, SDL3 as the platform layer.
All build/run logic lives in `build.odin` — run it with odin itself.

## Build & run

```sh
odin run . -- desktop    # macOS (Homebrew SDL3) or Linux (SDL3 built from deps/SDL3-3.2.28)
odin run . -- android    # NDK build, gradle APK, adb install + launch
odin run . -- ios        # xcodegen + xcodebuild simulator app (macOS)
```

`desktop` is the default. Env: `SAMPLE_ID` (0–11), `SMOKE_FRAMES` (exit after N frames).

## Samples (SAMPLE_ID)

0 triangle · 1 quad · 2 mandelbrot · 3 cube · 4 instancing · 5 offscreen ·
6 dyntex · 7 mrt · 8 blend · 9 shapes · 10 sgl · 11 debugtext

## Layout

- `app/` — all Odin code (`main.odin`, `samples.odin`, `math4.odin`)
- `vendors/sokol/` — vendored sokol C headers (the only C)
- `vendors/{sg,sgl,sdtx,sshape}/` — Odin bindings for those headers
- `vendors/shaders/` — sokol-shdc-generated Odin shader bindings
- `shaders/samples/*.glsl` — shader sources; regenerate bindings with
  `python3 scripts/shdc.py` after editing

The vendored sokol headers are the only C in the build: compiled straight
from the headers with impl defines, per platform, by whatever clang the
host provides (desktop), the NDK (android), or Xcode (ios).
