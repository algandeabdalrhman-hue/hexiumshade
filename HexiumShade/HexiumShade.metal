#include <metal_stdlib>
using namespace metal;

// Basic Metal compute-kernel test.
// This confirms the project can compile a Metal shader.

kernel void hexiumshade_passthrough(
    device const float4 *input [[buffer(0)]],
    device float4 *output [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    output[id] = input[id];
}
