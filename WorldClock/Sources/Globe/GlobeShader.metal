#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

// The canonical day/night terminator blend (see docs/research/globe-rendering.md):
// l = dot(normal, sunDirection); smoothstep a ~6°-wide twilight band around 0.
// Night lights in emissiveColor, elevation in roughness, water mask in custom,
// and sun direction in custom.vector (xyz).
// Unlit lighting model: we write the final color to
// emissive.
[[visible]]
void globeSurface(realitykit::surface_parameters params)
{
    constexpr sampler linearSampler(address::repeat, filter::linear, mip_filter::linear);

    // Use the same geographic frame as markers, picking, and the sun.
    // The bundled maps run west → east and north → south. Generated mesh
    // UVs do not define our geographic origin or longitude direction.
    float3 normal = normalize(params.geometry().model_position());
    float2 uv = float2(
        0.5 + atan2(-normal.z, normal.x) / (2.0 * M_PI_F),
        0.5 - asin(clamp(normal.y, -1.0, 1.0)) / M_PI_F
    );

    half3 nightColor = params.textures().emissive_color().sample(linearSampler, uv).rgb;

    // The sphere is unrotated, so the model normal is the world normal.
    float3 viewDirection = normalize(params.geometry().view_direction());
    float3 sunDirection = normalize(params.uniforms().custom_parameter().xyz);
    float ndotl = dot(normal, sunDirection);
    float facing = saturate(dot(normal, viewDirection));

    constexpr sampler mapSampler(s_address::repeat, t_address::clamp_to_edge,
                                 filter::linear, mip_filter::linear);
    half water = smoothstep(0.25h, 0.75h, params.textures().custom().sample(mapSampler, uv).r);

    // NASA/GEBCO elevation, scaled 0–6400 m. Exaggerate slopes gently
    // for a matte relief, without displacing the coastline or markers.
    auto elevationMap = params.textures().roughness();
    half elevation = elevationMap.sample(mapSampler, uv).r;
    float latitudeRadius = max(length(normal.xz), 0.15);
    float2 step = float2(1.0 / (2700.0 * latitudeRadius), 1.0 / 2700.0);
    float eastHeight = float(elevationMap.sample(mapSampler, uv + float2(step.x, 0)).r);
    float westHeight = float(elevationMap.sample(mapSampler, uv - float2(step.x, 0)).r);
    float northHeight = float(elevationMap.sample(mapSampler, uv - float2(0, step.y)).r);
    float southHeight = float(elevationMap.sample(mapSampler, uv + float2(0, step.y)).r);
    float2 slope = float2(eastHeight - westHeight, northHeight - southHeight) * 0.006
        / float2(4.0 * M_PI_F * step.x * latitudeRadius, 2.0 * M_PI_F * step.y);
    slope = clamp(slope, -0.45, 0.45);
    float longitude = (uv.x - 0.5) * 2.0 * M_PI_F;
    float3 east = float3(-sin(longitude), 0, -cos(longitude));
    float3 north = cross(normal, east);
    float3 terrainNormal = normalize(normal - east * slope.x - north * slope.y);
    // A soft northwest fill keeps mountains legible even at local noon.
    float3 reliefLight = normalize(normal + north * 0.7 - east * 0.6);
    half relief = half(0.72 + 0.36 * saturate(dot(terrainNormal, reliefLight)));
    half3 land = mix(half3(0.43h, 0.61h, 0.53h), half3(0.76h, 0.78h, 0.67h),
                     smoothstep(0.03h, 0.75h, elevation)) * relief;

    // A softened land mask adds a narrow turquoise coastal tint.
    // This is a cartographic accent, not a bathymetry measurement.
    half coast = water * saturate((1.0h - params.textures().custom().sample(mapSampler, uv, level(4.0)).r) * 2.5h);
    half3 ocean = mix(half3(0.014h, 0.055h, 0.11h), half3(0.025h, 0.12h, 0.18h), half(saturate(ndotl)));
    ocean = mix(ocean, half3(0.055h, 0.30h, 0.31h), coast * 0.65h);
    half3 daylight = mix(land, ocean, water);
    daylight *= half(0.62 + 0.38 * max(ndotl, 0.0));
    half3 darkness = mix(land * 0.16h, half3(0.009h, 0.022h, 0.045h), water);
    half light = half(smoothstep(-0.12, 0.18, ndotl));
    half3 color = mix(darkness, daylight, light);
    // Retain only the brighter Black Marble settlements, with capped
    // warmth so the selected city's orange marker remains dominant.
    half cityLight = smoothstep(0.13h, 0.5h, max(nightColor.r, max(nightColor.g, nightColor.b)));
    color += half3(0.72h, 0.41h, 0.16h) * cityLight * (1.0h - light) * (1.0h - water) * 0.38h;
    color += half3(0.12h, 0.30h, 0.33h) * half(pow(1.0 - facing, 4.0)) * (0.025h + 0.09h * light);
    params.surface().set_emissive_color(color);
    params.surface().set_base_color(half3(0.0h));
    params.surface().set_roughness(1.0h);
}

// A translucent shell just above the surface: pure fresnel glow that reads
// as the atmosphere's halo around the limb.
[[visible]]
void atmosphereSurface(realitykit::surface_parameters params)
{
    float3 viewDirection = normalize(params.geometry().view_direction());
    float3 sunDirection = normalize(params.uniforms().custom_parameter().xyz);
    float3 normal = normalize(params.geometry().model_position());

    float facing = saturate(dot(normal, viewDirection));
    float rim = pow(1.0 - facing, 4.8);
    float sunlit = 0.15 + 0.85 * smoothstep(-0.2, 0.3, dot(normal, sunDirection));
    params.surface().set_emissive_color(half3(0.20h, 0.40h, 0.44h) * half(rim * sunlit));
    params.surface().set_base_color(half3(0.0h));
    params.surface().set_opacity(half(rim * sunlit) * 0.12h);
}
