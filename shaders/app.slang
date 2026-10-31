// The single Slang module for the whole app. scripts/shaders.py compiles it
// per entry point to GLSL for sokol's GL backend and embeds the sources as
// C strings (app/native/shaders_generated.h).
//
// Binding model (sokol GL backend): layout(binding=N) maps to
// sg_bindings.views[N]. The compute fills a storage buffer with
// [11, 14, 17, 20]; the fragment pass reads it back and encodes the values
// into the framebuffer alpha channel (verified by readback asserts).

[vk::binding(0, 0)] RWStructuredBuffer<uint> vals;

static const uint multiplier = 3;

[shader("compute")]
[numthreads(4, 1, 1)]
void cs_main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    vals[i] = i * multiplier + 11u;
}

struct VS_Out
{
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
}

[shader("vertex")]
VS_Out vs_main(uint vid : SV_VertexID)
{
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VS_Out o;
    o.pos = float4(p[vid], 0.5, 1);
    o.uv = p[vid] * 0.5 + 0.5;
    return o;
}

[shader("fragment")]
float4 ps_main(float2 uv : TEXCOORD0, float4 frag_pos : SV_Position) : SV_Target
{
    uint band = min(uint(frag_pos.x) / 120u, 3u);
    float v = float(vals[band]) / 255.0;
    return float4(1.0, 0.5, 0.25, v);
}
