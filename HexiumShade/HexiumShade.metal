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
static float hsRect(float2 p, float2 center, float2 halfSize) {
    float2 d = abs(p - center) - halfSize;
    return 1.0 - smoothstep(0.0, 0.006, max(d.x, d.y));
}

static float hsCircle(float2 p, float2 center, float radius) {
    return 1.0 - smoothstep(radius - 0.004, radius + 0.004, distance(p, center));
}

static float3 hsOver(float3 base, float3 color, float mask) {
    return mix(base, color, clamp(mask, 0.0, 1.0));
}

fragment float4 hexium_sceneFragment(HexiumSceneOut in [[stage_in]], constant float& time [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 p = uv;
    float3 sky = mix(float3(0.38, 0.66, 0.88), float3(0.70, 0.83, 0.91), smoothstep(0.0, 1.0, uv.y));
    float3 color = sky;

    float sun = hsCircle(p, float2(0.79, 0.79), 0.075);
    color = hsOver(color, float3(1.0, 0.88, 0.58), sun);

    // Flat, stepped clouds evoke the simple materials of classic-era scenes.
    float cloudDrift = fmod(time * 0.012, 1.25) - 0.12;
    float2 cloudA = float2(cloudDrift, 0.76);
    float cloud = max(hsRect(p, cloudA, float2(0.075, 0.018)),
                  max(hsRect(p, cloudA + float2(-0.045, 0.012), float2(0.035, 0.018)),
                      hsRect(p, cloudA + float2(0.045, 0.010), float2(0.040, 0.015))));
    float2 cloudB = float2(0.43 - cloudDrift * 0.45, 0.88);
    cloud = max(cloud, max(hsRect(p, cloudB, float2(0.055, 0.014)),
                       hsRect(p, cloudB + float2(0.035, 0.009), float2(0.030, 0.012))));
    color = hsOver(color, float3(0.94, 0.97, 0.98), cloud);

    // Distant low-poly hills and a broad, flat grass plane.
    float hillLine = 0.34 + 0.055 * sin(uv.x * 7.0) + 0.018 * sin(uv.x * 17.0);
    color = hsOver(color, float3(0.32, 0.57, 0.39), 1.0 - smoothstep(hillLine - 0.004, hillLine + 0.004, uv.y));
    color = hsOver(color, float3(0.30, 0.62, 0.30), 1.0 - smoothstep(0.255, 0.263, uv.y));

    // A simple block-built platform with a darker front face.
    float platformTop = hsRect(p, float2(0.50, 0.285), float2(0.33, 0.035));
    float platformFront = hsRect(p, float2(0.50, 0.235), float2(0.33, 0.015));
    color = hsOver(color, float3(0.69, 0.48, 0.28), platformFront);
    color = hsOver(color, float3(0.82, 0.64, 0.39), platformTop);
    color = hsOver(color, float3(0.48, 0.31, 0.19), hsRect(p, float2(0.50, 0.235), float2(0.33, 0.0015)));

    // Blocky trees made from rectangular trunks and stepped leaf cubes.
    float tree1 = hsRect(p, float2(0.12, 0.36), float2(0.014, 0.085));
    color = hsOver(color, float3(0.38, 0.23, 0.13), tree1);
    float leaves1 = max(hsRect(p, float2(0.12, 0.48), float2(0.075, 0.055)),
                    max(hsRect(p, float2(0.075, 0.445), float2(0.040, 0.035)),
                        hsRect(p, float2(0.165, 0.445), float2(0.040, 0.035))));
    color = hsOver(color, float3(0.19, 0.43, 0.20), leaves1);

    float tree2 = hsRect(p, float2(0.88, 0.37), float2(0.012, 0.075));
    color = hsOver(color, float3(0.39, 0.24, 0.14), tree2);
    float leaves2 = max(hsRect(p, float2(0.88, 0.48), float2(0.065, 0.050)),
                    max(hsRect(p, float2(0.84, 0.45), float2(0.035, 0.030)),
                        hsRect(p, float2(0.92, 0.45), float2(0.035, 0.030))));
    color = hsOver(color, float3(0.17, 0.40, 0.18), leaves2);

    // Original block-avatar illustration: square head, torso, arms and legs.
    float bob = 0.004 * sin(time * 2.0);
    float shadow = hsRect(p, float2(0.51, 0.315), float2(0.095, 0.009));
    color = hsOver(color, float3(0.20, 0.34, 0.20), shadow);
    float leftLeg = hsRect(p, float2(0.475, 0.365 + bob), float2(0.020, 0.052));
    float rightLeg = hsRect(p, float2(0.525, 0.365 + bob), float2(0.020, 0.052));
    color = hsOver(color, float3(0.18, 0.28, 0.67), max(leftLeg, rightLeg));
    float torso = hsRect(p, float2(0.50, 0.465 + bob), float2(0.055, 0.065));
    color = hsOver(color, float3(0.84, 0.24, 0.16), torso);
    float arms = max(hsRect(p, float2(0.425, 0.465 + bob), float2(0.020, 0.055)),
                     hsRect(p, float2(0.575, 0.465 + bob), float2(0.020, 0.055)));
    color = hsOver(color, float3(0.91, 0.70, 0.48), arms);
    float head = hsRect(p, float2(0.50, 0.585 + bob), float2(0.047, 0.047));
    color = hsOver(color, float3(0.93, 0.72, 0.50), head);
    float face = max(hsRect(p, float2(0.485, 0.592 + bob), float2(0.004, 0.005)),
                     hsRect(p, float2(0.515, 0.592 + bob), float2(0.004, 0.005)));
    color = hsOver(color, float3(0.12, 0.12, 0.12), face);
    float smile = hsRect(p, float2(0.50, 0.570 + bob), float2(0.010, 0.002));
    color = hsOver(color, float3(0.35, 0.16, 0.12), smile);

    // Slightly soften highlights without modern bloom-heavy lighting.
    color = mix(color, color * 1.025 + float3(0.008), 0.22);
    return float4(clamp(color, 0.0, 1.0), 1.0);
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
