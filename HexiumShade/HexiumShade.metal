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


struct HexiumSceneOut { float4 position [[position]]; float2 uv; };
vertex HexiumSceneOut hexium_sceneVertex(uint id [[vertex_id]]) {
    const float2 p[3] = {float2(-1.0,-1.0),float2(3.0,-1.0),float2(-1.0,3.0)};
    HexiumSceneOut o; o.position=float4(p[id],0.0,1.0); o.uv=p[id]*0.5+0.5; return o;
}
fragment float4 hexium_sceneFragment(HexiumSceneOut in [[stage_in]], constant float& time [[buffer(0)]]) {
    float2 uv=in.uv;
    float3 base=mix(float3(0.015,0.035,0.09),float3(0.08,0.22,0.42),uv.y);
    float2 p1=float2(0.35+0.12*sin(time*0.7),0.48+0.10*cos(time*0.9));
    float2 p2=float2(0.72+0.10*cos(time*0.55),0.56+0.12*sin(time*0.8));
    float r1=length((uv-p1)*float2(1.0,1.35));
    float r2=length((uv-p2)*float2(1.0,1.35));
    float glow1=exp(-r1*r1*24.0);
    float glow2=exp(-r2*r2*30.0);
    base+=float3(0.10,0.48,1.0)*glow1+float3(0.72,0.18,0.95)*glow2;
    float grid=step(0.985,fract(uv.x*24.0))*0.06+step(0.985,fract(uv.y*16.0))*0.06;
    base+=grid;
    return float4(base,1.0);
}
vertex HexiumSceneOut hexium_displayVertex(uint id [[vertex_id]]) {
    const float2 p[3] = {float2(-1.0,-1.0),float2(3.0,-1.0),float2(-1.0,3.0)};
    HexiumSceneOut o; o.position=float4(p[id],0.0,1.0); o.uv=p[id]*0.5+0.5; return o;
}
fragment float4 hexium_displayFragment(HexiumSceneOut in [[stage_in]],
                                       texture2d<float> image [[texture(0)]],
                                       sampler smp [[sampler(0)]]) {
    return image.sample(smp,in.uv);
}
