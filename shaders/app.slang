// The single Slang module for the whole app. scripts/shaders.py compiles it
// per entry point to GLSL for sokol's GL backend and embeds the sources as
// C strings (app/native/shaders_generated.h).
//
// Binding model (sokol GL backend): layout(binding=N) maps to
// sg_bindings.views[N]. The compute fills a storage buffer with
// [11, 14, 17, 20]; the fragment pass reads it back and encodes the values
// into the framebuffer alpha channel (verified by readback asserts).

[vk::binding(0, 0)] RWTexture2D<float4> rw_img;   // compute: storage image write
[vk::binding(1, 0)] Texture2D<float4> img_tex;    // render: sampled read
[vk::binding(2, 0)] SamplerState img_smp;         // render: sampler for the pair

static const uint multiplier = 3;

[shader("compute")]
[numthreads(4, 1, 1)]
void cs_main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    rw_img[uint2(i, 0)] = float4(1.0, 0.5, 0.25, float(i * multiplier + 11u) / 255.0);
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
    // the compute-encoded result travels in the image alpha channel;
    // band centers land exactly on texel centers (480 / 4 bands)
    float v = img_tex.SampleLevel(img_smp, uv, 0).a;
    return float4(v, v, v, 1.0); // value in every color channel: channel-order agnostic
}
