//
//  VFDShaders.metal
//  VFD Visualizer
//
//  Created by Milo Powell on 1/17/26.
//


#include <metal_stdlib>
using namespace metal;

struct VisualizerUniforms {
    float3 activeColorLow;
    float3 activeColorHigh;
    float3 inactiveColor;
    int numBars;
    float showPeaks; // 1.0 for true, 0.0 for false
    float barSpacing;
    float standby; // 1.0 while OFFLINE, 0.0 while capturing
};

// Ensures the vertex output matches the fragment input
struct RasterData {
    float4 position [[position]]; // For GPU to draw pixels
    float2 uv;                    // Pass to fragment shader
};

// Vertex shader (standard quad)
vertex RasterData vfd_vertex(uint vertexID [[vertex_id]]) {
    // Define the 4 corners of the screen for a rectangle strip
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0), // Bottom left
        float4( 1.0, -1.0, 0.0, 1.0), // Bottom right
        float4(-1.0,  1.0, 0.0, 1.0), // Top left
        float4( 1.0,  1.0, 0.0, 1.0)  // Top right
    };
    
    float2 uvs[4] = {
        float2(0.0, 0.0), // Bottom left
        float2(1.0, 0.0), // Bottom right
        float2(0.0, 1.0), // Top left
        float2(1.0, 1.0)  // Top right
    };

    RasterData out;
    out.position = positions[vertexID];
    out.uv = uvs[vertexID];
    return out;
}

// Fragment shader
fragment float4 vfd_fragment(RasterData in [[stage_in]],
                             constant float *magnitudes [[buffer(0)]],
                             constant VisualizerUniforms &theme [[buffer(1)]],
                             constant float *peaks [[buffer(2)]])
{
    float2 uv = in.uv;
    
    // Collect bar index once
    float numBarsF = float(theme.numBars);
    int barIndex = clamp(int(uv.x * numBarsF), 0, theme.numBars - 1);
    
    // Collect amplitude & peaks for each bar
    float amplitude = magnitudes[barIndex];
    float peakValue = peaks[barIndex];
    
    float localX = fract(uv.x * float(theme.numBars));
    float localY = fract(uv.y * 30.0);
    
    // Gaps between individual boxes
    float isBarGap = (localX > 0.1 && localX < 0.9 && localY > 0.1 && localY < 0.9) ? 1.0 : 0.0;
    
    // Main bar logic
    // Light whole segments only, so the top of the bar lines up with the segment grid
    // and the peak caps. A segment lights once the level reaches half of it.
    float litRows = floor(amplitude * 30.0 + 0.5);
    float isBar = (floor(uv.y * 30.0) < litRows) ? 1.0 : 0.0;
    // Height of the lit bar, in the same 0 to 1 units as amplitude
    float level = litRows / 30.0;
    
    // Peak floating cap logic
    // The cap is one whole segment, like the peak light on a hardware meter,
    // so it lines up with the segment grid instead of cutting across the gaps
    float isPeak = 0.0;
    if (theme.showPeaks == 1 && peakValue > 0.0) {
        // Row of the top segment a bar at the peak's level would light, using the same
        // rounding as the bar, so a cap riding on a rising bar sits on its top segment
        float peakRow = floor(min(peakValue, 1.0) * 30.0 + 0.5) - 1.0;
        isPeak = (floor(uv.y * 30.0) == peakRow) ? 1.0 : 0.0;
    }
    
    // VFD glow logic
    // Distance from current pixel y to top of the lit bar
    float dist = abs(uv.y - level);
    // Inverse distance to create a bloom
    float glow = 0.02 / (dist + 0.05);
    // Standby (OFFLINE): the display is powered down, so no glow
    glow *= (1.0 - theme.standby);
    
    // Color mixing
    float3 activeGradient = mix(theme.activeColorLow, theme.activeColorHigh, uv.y);
    
    // Inactive or active bar
    float3 color = mix(theme.inactiveColor, activeGradient, isBar);

    // Standby: dim the unlit segments, and keep the bottom row faintly lit,
    // like a hardware meter that's switched on but idle
    if (theme.standby == 1.0) {
        color = mix(theme.inactiveColor * 0.6, activeGradient, isBar);
        // Only where no bar is lit, so a bar still falling after a stop keeps its bottom segment
        if (floor(uv.y * 30.0) == 0.0 && isBar == 0.0) {
            color = theme.activeColorLow * 0.35;
        }
    }
    
    // Peak cap, brighter than the bar's top color so it stands out
    color = mix(color, theme.activeColorHigh + 0.2, isPeak);
    
    // Add glow
    color += (activeGradient * glow * 0.5) * isBarGap;
    
    return float4(color * isBarGap, 1.0);
}
    
