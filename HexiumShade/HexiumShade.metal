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
