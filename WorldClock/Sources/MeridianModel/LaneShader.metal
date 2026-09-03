#include <metal_stdlib>
using namespace metal;

// The Meridian lane shader (SwiftUI colorEffect): each lane is a tiny
// 24-hour landscape panorama of its city. The pixel's x is an hour of the
// home civil day; the sampled sun-altitude curve drives everything — a
// painterly sky (night indigo → dawn fire → day blue), stars in deep night,
// the sun's real arc glowing across the daylight section, drifting cell-hash
// clouds, and two parallax hill silhouettes (techniques after the classic
// Shadertoy stylized-landscape scenes). Time Travel applies an amber grade.

static float laneHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float laneHash1(float x) {
    return fract(sin(x * 234.56) * 5678.9);
}

static float laneAltitude(device const float *altitudes, int count, float x) {
    float t = clamp(x, 0.0, 1.0) * float(count - 1);
    int lower = int(floor(t));
    int upper = min(lower + 1, count - 1);
    return mix(altitudes[lower], altitudes[upper], t - float(lower));
}

/// Blobby cloud built from smoothstepped discs in a repeating cell, the
/// Shadertoy way: one cloud per unit cell, jittered by the cell's hash.
static float cloudMask(float2 p) {
    float id = floor(p.x);
    float n = laneHash1(id) * 2.0 - 1.0;
    p.x = fract(p.x) - 0.5;
    float2 q = p - float2(n * 0.3, 0.05 + n * 0.12);
    q.y *= 1.6;
    float c = smoothstep(0.015, -0.015, length(q) - 0.14);
    c += smoothstep(0.015, -0.015, length(q + float2(0.11, 0.05)) - 0.09);
    c += smoothstep(0.015, -0.015, length(q + float2(-0.12, 0.04)) - 0.11);
    c += smoothstep(0.015, -0.015, length(q + float2(-0.02, -0.05)) - 0.08);
    return clamp(c, 0.0, 1.0) * (0.35 + 0.5 * laneHash1(id + 7.0));
}

/// Rolling ridge line: stacked sines, phase-shifted per lane.
static float hillHeight(float x, float phase) {
    return sin(x * 1.5 + phase) * sin(x * 0.8 + phase * 1.7) * 0.5;
}

[[ stitchable ]] half4 meridianLane(
    float2 position,
    half4 source,
    float2 size,
    device const float *altitudes,
    int count,
    float seed,
    float time,
    float tintStrength
) {
    if (source.a <= 0.0h || count < 2 || size.x <= 0.0 || size.y <= 0.0) {
        return source;
    }
    float2 uv = position / size;              // x: the day, y: 0 top → 1 bottom
    float2 scene = float2(position.x / size.y, uv.y); // square units for shapes
    float altitude = laneAltitude(altitudes, count, uv.x);

    // Time of day at this column, and the dawn/dusk band around the horizon.
    float tod = smoothstep(-12.0, 15.0, altitude);
    float dusk = exp(-pow(altitude / 6.0, 2.0));

    // Sky: vertical gradient between night and day palettes, horizon fired
    // by the dusk band (strongest near the bottom, a violet kiss on top).
    float3 top = mix(float3(0.05, 0.07, 0.16), float3(0.30, 0.58, 0.90), tod);
    float3 bottom = mix(float3(0.10, 0.13, 0.25), float3(0.62, 0.82, 0.95), tod);
    bottom = mix(bottom, float3(1.00, 0.55, 0.30), dusk * 0.85);
    top = mix(top, float3(0.45, 0.28, 0.42), dusk * 0.5);
    float3 col = mix(top, bottom, uv.y);

    // Stars fade in below -6° altitude, gently twinkling.
    float starVisibility = 1.0 - smoothstep(-14.0, -6.0, altitude);
    if (starVisibility > 0.0) {
        float2 shifted = position + float2(seed * 37.0, seed * 11.0);
        float2 cell = floor(shifted / 5.0);
        float pick = laneHash(cell);
        if (pick > 0.972) {
            float2 center = (cell + 0.5
                + 0.6 * (float2(laneHash(cell + 1.3), laneHash(cell + 2.7)) - 0.5)) * 5.0;
            float distance2 = dot(shifted - center, shifted - center);
            float brightness = (pick - 0.972) / 0.028;
            float twinkle = 0.75 + 0.25 * sin(time * 2.5 + pick * 40.0);
            col += float3(0.92, 0.95, 1.0) * exp(-distance2 * 2.0)
                * brightness * starVisibility * twinkle;
        }
    }

    // The sun's real arc: a warm glow tracing its altitude across the day.
    float sunY = 0.78 - clamp(altitude, 0.0, 70.0) / 70.0 * 0.55;
    float arc = exp(-pow((uv.y - sunY) * 7.0, 2.0)) * smoothstep(-2.0, 6.0, altitude);
    col += float3(1.0, 0.75, 0.35) * arc * 0.30;

    // Clouds drift slowly; dim and cool at night, bright by day.
    float cloud = cloudMask(float2(scene.x * 0.55 + time * 0.02 + seed * 3.1, uv.y - 0.28));
    float3 cloudColor = mix(float3(0.28, 0.31, 0.45), float3(1.0, 0.98, 0.95), tod);
    cloudColor = mix(cloudColor, float3(1.0, 0.7, 0.5), dusk * 0.5);
    col = mix(col, cloudColor, cloud * (0.35 + 0.45 * tod));

    // Two parallax ridge lines along the bottom; night flattens them into
    // near-black silhouettes, day lifts them muted green-teal.
    float farY = 0.74 + hillHeight(scene.x * 0.9 + seed * 2.3, seed) * 0.16;
    float farMask = smoothstep(-0.02, 0.02, uv.y - farY);
    float3 farColor = mix(float3(0.09, 0.11, 0.20), float3(0.34, 0.52, 0.48), tod);
    farColor = mix(farColor, float3(0.80, 0.44, 0.32), dusk * 0.35);
    col = mix(col, farColor, farMask);

    float nearY = 0.88 + hillHeight(scene.x * 1.7 + seed * 4.1, seed * 1.7) * 0.12;
    float nearMask = smoothstep(-0.025, 0.025, uv.y - nearY);
    float3 nearColor = mix(float3(0.05, 0.07, 0.14), float3(0.20, 0.40, 0.36), tod);
    col = mix(col, nearColor, nearMask);

    // Time Travel: amber grade over the whole scene.
    if (tintStrength > 0.0) {
        float luminance = dot(col, float3(0.299, 0.587, 0.114));
        float3 amber = luminance * float3(1.30, 0.95, 0.58);
        col = mix(col, amber, tintStrength);
    }

    // Ordered-noise dither: one LSB, enough to break gradient banding.
    col += (laneHash(position) - 0.5) / 128.0;

    return half4(half3(saturate(col)), 1.0h) * source.a;
}
