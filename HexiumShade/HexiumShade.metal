#include <metal_stdlib>
using namespace metal;

struct HexiumShadeUniforms {
    float exposure;
    float contrast;
    float saturation;
    float bloomIntensity;
    float sharpenAmount;
    float ambientIntensity;
    uint flags;
};

enum {
    HexiumEffectBloom = 1u << 0,
    HexiumEffectSharpen = 1u << 1,
    HexiumEffectColorCorrection = 1u << 2,
    HexiumEffectAmbientLight = 1u << 3
};

static float3 hexiumReadRGB(texture2d<float, access::read> tex,
                            int2 position,
                            uint2 dimensions) {
    int2 upper = int2(dimensions) - int2(1);
    uint2 safePosition = uint2(clamp(position, int2(0), upper));
    return tex.read(safePosition).rgb;
}

kernel void hexiumshade_applyEffects(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant HexiumShadeUniforms& settings [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {

    uint2 dimensions = uint2(source.get_width(), source.get_height());
    if (gid.x >= dimensions.x || gid.y >= dimensions.y) return;

    float4 original = source.read(gid);
    float3 color = original.rgb;

    if ((settings.flags & HexiumEffectBloom) != 0) {
        float3 glow = float3(0.0);
        float weight = 0.0;
        for (int y = -2; y <= 2; ++y) {
            for (int x = -2; x <= 2; ++x) {
                float3 sampleColor = hexiumReadRGB(source, int2(gid) + int2(x, y), dimensions);
                float luminance = dot(sampleColor, float3(0.2126, 0.7152, 0.0722));
                float contribution = max(luminance - 0.68, 0.0);
                float kernelWeight = (x == 0 && y == 0) ? 1.0 : 0.65;
                glow += sampleColor * contribution * kernelWeight;
                weight += kernelWeight;
            }
        }
        color += (glow / max(weight, 0.001)) * settings.bloomIntensity * 2.0;
    }

    if ((settings.flags & HexiumEffectSharpen) != 0) {
        float3 north = hexiumReadRGB(source, int2(gid) + int2(0, -1), dimensions);
        float3 south = hexiumReadRGB(source, int2(gid) + int2(0, 1), dimensions);
        float3 east  = hexiumReadRGB(source, int2(gid) + int2(1, 0), dimensions);
        float3 west  = hexiumReadRGB(source, int2(gid) + int2(-1, 0), dimensions);
        float3 blur = (north + south + east + west) * 0.25;
        color += (original.rgb - blur) * settings.sharpenAmount;
    }

    if ((settings.flags & HexiumEffectAmbientLight) != 0) {
        float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        float shadowLift = 1.0 - smoothstep(0.04, 0.62, luminance);
        color += settings.ambientIntensity * shadowLift;
    }

    if ((settings.flags & HexiumEffectColorCorrection) != 0) {
        color *= exp2(settings.exposure);
        color = (color - 0.5) * settings.contrast + 0.5;
        float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        color = mix(float3(luminance), color, settings.saturation);
    }

    destination.write(float4(clamp(color, 0.0, 1.0), original.a), gid);
}
