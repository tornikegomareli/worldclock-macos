---
status: accepted (spike verified, 2026-09-02)
---

# Globe rendering: RealityKit first, custom Metal as fallback

SceneKit — the traditional choice — is deprecated as of macOS 26 (WWDC25 session 288: critical-bug-only maintenance), so it is off the table for a new app. Research (`docs/research/globe-rendering.md`) verified that everything the globe needs exists in RealityKit on macOS 15: `RealityView`, `.realityViewCameraControls(.orbit)`, `CustomMaterial` with Metal surface shaders for the day/night terminator, and `RealityCoordinateSpaceProjecting` for picking and marker projection.

Decision: build the globe on RealityKit, gated by a prototype spike whose go/no-go question is whether `CustomMaterial` works inside `RealityView` on macOS (documented parts, no prior art for the combination). If the spike fails, fall back to a custom `MTKView` — one sphere, one terminator shader, hand-rolled arcball camera and ray-sphere picking.

The terminator technique is the same either way: `smoothstep` on `dot(normal, sunDirection)` blending NASA Blue Marble (day) and Black Marble (night) textures, both public domain (credit "NASA Earth Observatory").

## Spike verdict (issue #14): GO

The spike (`prototype/globe-spike`, never merged) rendered the full target on macOS 26: Date-driven terminator, atmosphere rim + halo shell, ocean sun glint via a water mask in the spare texture slot, click → lat/lon picking, and sub-millisecond material updates at per-frame scrub rates. Human-reviewed and accepted.

Findings that bind #15's implementation:

- **Camera controls are ours.** `.realityViewCameraControls(.orbit)` has fixed drag sensitivity, no scroll-wheel zoom on macOS, and fights an explicitly added camera. Use a manual `PerspectiveCamera` on spherical coordinates (drag = yaw/pitch, scroll/pinch = dolly).
- **Coordinate frame (corrected September 2026).** Visual Jump testing exposed a mismatch between the generated sphere's UVs and the city coordinates. The shader now derives equirectangular UVs directly from model position, with Greenwich at +X, north at +Y, and east toward −Z. Markers, picking, the camera, and the sun use that same frame. This replaces the spike's incorrect reliance on generated UVs and +Z east longitudes.
- **Surface shader API.** `view_direction()` points fragment → camera; `world_normal` is not exposed (the unrotated sphere's model normal stands in); the uniform slot is `custom.value` (SIMD4), not `custom.vector`; the generated sphere's V coordinate is flipped.
- **Texture loading.** `TextureResource.load(named:)` requires an asset catalog once PNGs are involved; load by bundle URL with an explicit semantic — `.color` for sRGB imagery, `.raw` for masks — or the day side renders gamma-crushed.
- **Night texture.** Black Marble's moonlit ice reads as a bright blob; subtract the diffuse base before boosting so only city lights survive.
- **Textures at 8192×4096** (downsampled from NASA originals) are sharp at all panel-relevant zooms; the equirectangular pole pinch is visible only when zooming a pole directly.
