---
status: proposed (pending prototype spike)
---

# Globe rendering: RealityKit first, custom Metal as fallback

SceneKit — the traditional choice — is deprecated as of macOS 26 (WWDC25 session 288: critical-bug-only maintenance), so it is off the table for a new app. Research (`docs/research/globe-rendering.md`) verified that everything the globe needs exists in RealityKit on macOS 15: `RealityView`, `.realityViewCameraControls(.orbit)`, `CustomMaterial` with Metal surface shaders for the day/night terminator, and `RealityCoordinateSpaceProjecting` for picking and marker projection.

Decision: build the globe on RealityKit, gated by a prototype spike whose go/no-go question is whether `CustomMaterial` works inside `RealityView` on macOS (documented parts, no prior art for the combination). If the spike fails, fall back to a custom `MTKView` — one sphere, one terminator shader, hand-rolled arcball camera and ray-sphere picking.

The terminator technique is the same either way: `smoothstep` on `dot(normal, sunDirection)` blending NASA Blue Marble (day) and Black Marble (night) textures, both public domain (credit "NASA Earth Observatory").
