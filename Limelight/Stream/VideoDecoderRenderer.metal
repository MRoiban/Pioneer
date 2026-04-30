#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };

    float2 texCoords[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0),
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> yTexture [[texture(0)]],
                              texture2d<float, access::sample> cbcrTexture [[texture(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float y = yTexture.sample(textureSampler, in.texCoord).r;
    float2 cbcr = cbcrTexture.sample(textureSampler, in.texCoord).rg;

    float yVideo = max((y - (16.0 / 255.0)) * (255.0 / 219.0), 0.0);
    float cb = cbcr.x - 0.5;
    float cr = cbcr.y - 0.5;

    float3 rgb;
    rgb.r = yVideo + 1.5748 * cr;
    rgb.g = yVideo - 0.1873 * cb - 0.4681 * cr;
    rgb.b = yVideo + 1.8556 * cb;

    return float4(saturate(rgb), 1.0);
}
