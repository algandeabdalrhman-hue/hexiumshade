#include <metal_stdlib>
using namespace metal;

// Standalone post-processing pass for textures owned by the host application.
// The caller supplies a readable texture and receives a separate output texture.
kernel void hexiumshade_color_grade(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant float4 &controls [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) return;

    float4 color = source.read(gid);
    float3 rgb = color.rgb;

    rgb += controls.x;
    rgb = (rgb - 0.5f) * controls.y + 0.5f;

    float luminance = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
    rgb = mix(float3(luminance), rgb, controls.z);

    destination.write(float4(clamp(rgb, 0.0f, 1.0f), color.a), gid);
}


struct HSMXAOControls {
    float4 parameters; // radius pixels, intensity, normal bias, depth encoding
    float4 camera;     // near plane, far plane, normal encoding, unused
};

static float hs_view_distance(float rawDepth, float nearPlane, float farPlane, int encoding) {
    if (encoding == 2) return max(rawDepth, nearPlane);
    if (encoding == 1) return mix(nearPlane, farPlane, saturate(rawDepth));
    // Conventional Metal [0,1] device-Z depth (near=0, far=1).
    float z = saturate(rawDepth);
    return (nearPlane * farPlane) / max(farPlane - z * (farPlane - nearPlane), 1e-5f);
}

// Screen-space ambient occlusion approximation. The host must supply matching,
// readable depth and normal textures; no scene interception or depth guessing occurs.
kernel void hexiumshade_mxao(
    texture2d<float, access::read> colorTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::read> normalTexture [[texture(2)]],
    texture2d<float, access::write> outputTexture [[texture(3)]],
    constant HSMXAOControls &controls [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float4 source = colorTexture.read(gid);
    float centerRaw = depthTexture.read(gid).r;
    float centerDistance = hs_view_distance(centerRaw, controls.camera.x, controls.camera.y,
                                            int(controls.parameters.w));
    float3 centerNormal = normalTexture.read(gid).xyz;
    if (controls.camera.z > 1.5f) centerNormal = centerNormal * 2.0f - 1.0f;
    centerNormal = normalize(centerNormal);

    const int2 directions[8] = {
        int2(1, 0), int2(-1, 0), int2(0, 1), int2(0, -1),
        int2(1, 1), int2(-1, 1), int2(1, -1), int2(-1, -1)
    };
    float occlusion = 0.0f;
    float validSamples = 0.0f;
    int sampleRadius = max(1, int(round(controls.parameters.x)));

    for (uint i = 0; i < 8; ++i) {
        int2 samplePosition = int2(gid) + directions[i] * sampleRadius;
        samplePosition = clamp(samplePosition, int2(0), int2(int(width) - 1, int(height) - 1));
        uint2 sampleCoord = uint2(samplePosition);
        float sampleRaw = depthTexture.read(sampleCoord).r;
        float sampleDistance = hs_view_distance(sampleRaw, controls.camera.x, controls.camera.y,
                                                int(controls.parameters.w));
        float3 sampleNormal = normalTexture.read(sampleCoord).xyz;
        if (controls.camera.z > 1.5f) sampleNormal = sampleNormal * 2.0f - 1.0f;
        sampleNormal = normalize(sampleNormal);

        float depthDelta = centerDistance - sampleDistance;
        float normalAgreement = saturate(dot(centerNormal, sampleNormal));
        float threshold = max(controls.parameters.z * centerDistance, 0.0005f);
        float rangeWeight = saturate(1.0f - abs(depthDelta) / max(centerDistance * 0.35f, 0.01f));
        float blocked = smoothstep(threshold, threshold + max(centerDistance * 0.025f, 0.001f), depthDelta);
        occlusion += blocked * mix(0.35f, 1.0f, normalAgreement) * rangeWeight;
        validSamples += 1.0f;
    }

    float ao = saturate((occlusion / max(validSamples, 1.0f)) * controls.parameters.y);
    float ambientFactor = 1.0f - ao * 0.72f;
    outputTexture.write(float4(source.rgb * ambientFactor, source.a), gid);
}


struct HSDepthHazeControls {
    float4 fogColorStart; // linear RGB fog color, normalized fog start
    float4 depthControls; // fog factor, near plane, far plane, depth encoding
};

static float hs_haze_view_distance(float rawDepth, float nearPlane, float farPlane, int encoding) {
    if (encoding == 2) return max(rawDepth, nearPlane);
    if (encoding == 1) return mix(nearPlane, farPlane, saturate(rawDepth));
    float z = saturate(rawDepth);
    return (nearPlane * farPlane) / max(farPlane - z * (farPlane - nearPlane), 1e-5f);
}

// Depth haze/fog composite. Fog is blended in linear color space.
kernel void hexiumshade_depth_haze(
    texture2d<float, access::read> colorTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant HSDepthHazeControls &controls [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float4 source = colorTexture.read(gid);
    float rawDepth = depthTexture.read(gid).r;
    float viewDistance = hs_haze_view_distance(rawDepth, controls.depthControls.y,
                                               controls.depthControls.z,
                                               int(controls.depthControls.w));
    float normalizedDistance = saturate((viewDistance - controls.depthControls.y) /
                                        max(controls.depthControls.z - controls.depthControls.y, 1e-5f));
    float fogStart = controls.fogColorStart.w;
    float fogFactor = max(controls.depthControls.x, 1e-5f);
    float fogAmount = smoothstep(fogStart, min(1.0f, fogStart + fogFactor), normalizedDistance);
    float3 fogColor = controls.fogColorStart.rgb;
    float3 result = mix(source.rgb, fogColor, saturate(fogAmount));
    outputTexture.write(float4(result, source.a), gid);
}
