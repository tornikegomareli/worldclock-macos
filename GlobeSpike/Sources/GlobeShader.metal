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

    float3 normal = normalize(params.geometry().model_position());
    float3 sunDirection = normalize(params.uniforms().custom_parameter().xyz);
    float ndotl = dot(normal, sunDirection);

    // ~0.1-wide band in dot space ≈ real civil+nautical twilight width.
    float dayFactor = smoothstep(-0.03, 0.07, ndotl);
    // City lights fade out through twilight so they never glow in daylight;
    // a faint floor keeps the night side's landmass readable.
    half3 night = nightColor * half(1.0 - dayFactor) * 1.4h + half3(0.012h, 0.014h, 0.022h);
    half3 color = mix(night, dayColor, half(dayFactor));

    params.surface().set_emissive_color(color);
    params.surface().set_base_color(half3(0.0h));
    params.surface().set_roughness(1.0h);
}
