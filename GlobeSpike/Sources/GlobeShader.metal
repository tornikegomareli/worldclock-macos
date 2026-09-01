#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

// The canonical day/night terminator blend (see docs/research/globe-rendering.md):
// l = dot(normal, sunDirection); smoothstep a ~6°-wide twilight band around 0.
// Day texture in baseColor, night lights in emissiveColor, sun direction in
// custom.vector (xyz). Unlit lighting model: we write the final color to
// emissive.
[[visible]]
void globeSurface(realitykit::surface_parameters params)
{
    constexpr sampler linearSampler(address::repeat, filter::linear, mip_filter::linear);

    float2 uv = params.geometry().uv0();
    // RealityKit's generated sphere flips V relative to equirectangular maps.
    uv.y = 1.0 - uv.y;

    half3 dayColor = params.textures().base_color().sample(linearSampler, uv).rgb;
    half3 nightColor = params.textures().emissive_color().sample(linearSampler, uv).rgb;

    // The sphere is unrotated, so the model normal is the world normal.
    float3 normal = normalize(params.geometry().model_position());
    float3 viewDirection = normalize(params.geometry().view_direction());
    float3 sunDirection = normalize(params.uniforms().custom_parameter().xyz);
    float ndotl = dot(normal, sunDirection);

    // ~0.1-wide band in dot space ≈ real civil+nautical twilight width.
    float dayFactor = smoothstep(-0.03, 0.07, ndotl);

    // Night lights: gentle boost with a soft knee so cities glow richly
    // without clipping to white.
    half3 lights = nightColor * 1.6h;
    lights = lights / (1.0h + lights * 0.6h);
    half3 night = lights * half(1.0 - dayFactor) + half3(0.010h, 0.012h, 0.020h);

    half3 color = mix(night, dayColor, half(dayFactor));

    // Warm tint inside the twilight band — strongest right on the
    // terminator, fading both ways.
    float band = exp(-pow(ndotl / 0.09, 2.0));
    color += half3(0.85h, 0.38h, 0.12h) * half(band) * 0.18h;

    // Ocean sun glint: a tight mirror lobe on water only (mask in the custom
    // texture slot), day side only — the classic sunrise stripe on the sea.
    half waterMask = params.textures().custom().sample(linearSampler, uv).r;
    float3 reflected = reflect(-sunDirection, normal);
    float glint = pow(saturate(dot(reflected, -viewDirection)), 90.0);
    color += half3(1.0h, 0.90h, 0.72h) * half(glint) * waterMask * half(dayFactor) * 0.55h;

    // Atmospheric rim: blue scattering climbing toward the limb, stronger on
    // the day side, a whisper on the night side.
    float facing = saturate(dot(normal, -viewDirection));
    float rim = pow(1.0 - facing, 2.8);
    color += half3(0.24h, 0.42h, 0.85h) * half(rim) * half(0.10 + 0.45 * dayFactor);

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

    float facing = saturate(dot(normal, -viewDirection));
    float rim = pow(1.0 - facing, 3.2);
    // The halo also dims on the night side.
    float sunlit = 0.25 + 0.75 * smoothstep(-0.2, 0.3, dot(normal, sunDirection));

    params.surface().set_emissive_color(half3(0.30h, 0.50h, 0.95h) * half(rim * sunlit));
    params.surface().set_base_color(half3(0.0h));
    params.surface().set_opacity(half(rim * sunlit) * 0.55h);
}
