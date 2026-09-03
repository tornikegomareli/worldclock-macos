#include <metal_stdlib>
using namespace metal;

// The Meridian lane shader (SwiftUI colorEffect). Each pixel's x is an hour
// of the home civil day; the sampled sun-altitude curve drives a quiet 1D
// sky in the panel's own palette: night → day ramp with a warm twilight
// band, a luminous daylight wash that peaks at solar noon, deepened night
// with faint stars, and a dither that kills gradient banding. Time Travel's
// amber carries through the theme colors.

static float laneHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float laneAltitude(device const float *altitudes, int count, float x) {
    float t = clamp(x, 0.0, 1.0) * float(count - 1);
    int lower = int(floor(t));
    int upper = min(lower + 1, count - 1);
    return mix(altitudes[lower], altitudes[upper], t - float(lower));
}

[[ stitchable ]] half4 meridianLane(
    float2 position,
    half4 source,
    float2 size,
    device const float *altitudes,
    int count,
    half4 night,
    half4 twilight,
    half4 day,
    float seed
) {
    if (source.a <= 0.0h || count < 2 || size.x <= 0.0 || size.y <= 0.0) {
        return source;
    }
    float2 uv = position / size;
    float altitude = laneAltitude(altitudes, count, uv.x);

    // Base ramp: night → day by altitude, twilight as a band around 0°.
    float dayFactor = smoothstep(-8.0, 12.0, altitude);
    float3 col = mix(float3(night.rgb), float3(day.rgb), dayFactor);

    // Deep night sinks darker than the token, so midnight reads deeper than
    // the edges of dusk.
    col = mix(col * 0.72, col, smoothstep(-32.0, -10.0, altitude));

    float twilightBand = exp(-pow(altitude / 5.5, 2.0));
    col = mix(col, float3(twilight.rgb), twilightBand * 0.85);

    // The sun: a warm luminous wash over the daylight section, peaking at
    // solar noon and glowing a little stronger toward the top of the lane.
    float noon = pow(clamp(altitude, 0.0, 70.0) / 70.0, 1.6);
    col += float3(1.0, 0.88, 0.55) * noon * 0.22 * (0.7 + 0.6 * (1.0 - uv.y));

    // Faint stars in deep night.
    float starVisibility = 1.0 - smoothstep(-14.0, -6.0, altitude);
    if (starVisibility > 0.0) {
        float2 shifted = position + float2(seed * 37.0, seed * 11.0);
        float2 cell = floor(shifted / 5.0);
        float pick = laneHash(cell);
        if (pick > 0.976) {
            float2 center = (cell + 0.5
                + 0.6 * (float2(laneHash(cell + 1.3), laneHash(cell + 2.7)) - 0.5)) * 5.0;
            float distance2 = dot(shifted - center, shifted - center);
            float brightness = (pick - 0.976) / 0.024;
            col += float3(0.92, 0.95, 1.0) * exp(-distance2 * 2.4)
                * brightness * starVisibility * 0.9;
        }
    }

    // Faint top light / bottom shade so the bar reads as a solid, not a fill.
    col *= 1.0 + (0.5 - uv.y) * 0.09;

    // Ordered-noise dither: one LSB, enough to break banding.
    col += (laneHash(position) - 0.5) / 128.0;

    return half4(half3(saturate(col)), 1.0h) * source.a;
}
