# Globe Rendering: RealityKit vs Custom Metal

Date: 2026-08-31

Question: best approach for an interactive 3D Earth globe with a real-time day/night terminator (driven by an arbitrary simulated `Date`), city markers, drag-to-rotate, zoom, picking/hover, and time-scrub animation, in a native macOS 15+ Swift app, direct-distributed.

Availability claims below were verified against Apple's documentation JSON API (`developer.apple.com/tutorials/data/documentation/...`), which carries per-platform `introducedAt`/`deprecatedAt` fields. GitHub facts (license, last push) come from the GitHub API on 2026-08-31.

## Candidate A: RealityKit (RealityView)

Every API this app needs exists on macOS 15:

- [`RealityView`](https://developer.apple.com/documentation/realitykit/realityview): macOS 15.0+, iOS 18.0+ (verified via docs JSON).
- [`CustomMaterial`](https://developer.apple.com/documentation/realitykit/custommaterial): **macOS 12.0+, not deprecated** (verified). "A material that works with custom Metal shader functions." Unavailable on visionOS/tvOS<26, which does not affect this app. You supply a Metal [surface shader](https://developer.apple.com/documentation/realitykit/custommaterial/surfaceshader) (RealityKit's fragment stage) and optionally a geometry modifier; guide: [Modifying RealityKit rendering using custom materials](https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials) and the [RealityKit Custom Shader API PDF](https://developer.apple.com/metal/Metal-RealityKit-APIs.pdf). Texture slots available to the shader: `baseColor.texture` (day), `emissiveColor.texture` (night lights), plus a `custom.texture` and one `custom.vector` (float4 — enough for the sun direction uniform). With `lightingModel: .unlit` the shader does the whole day/night blend itself; no scene lights needed.
- [`ShaderGraphMaterial`](https://developer.apple.com/documentation/RealityKit/ShaderGraphMaterial): macOS 15.0+. **Reality Composer Pro is not required**: [`init(materialXLabel:data:)`](https://developer.apple.com/documentation/realitykit/shadergraphmaterial/init(materialxlabel:data:)) "Loads a ShaderGraphMaterial from MaterialX data" and is macOS 15.0+ (verified via docs JSON) — you can ship a `.mtlx` string and load it programmatically. `setParameter(name:value:)` updates parameters (e.g. sun direction) at runtime; materials are value types, so reassign the material to the `ModelComponent` after mutation.
- Camera: [`realityViewCameraControls(_:)`](https://developer.apple.com/documentation/swiftui/view/realityviewcameracontrols(_:)) (macOS 15.0+, verified) gives built-in `.orbit`/`.dolly`/`.pan` gestures — drag-to-rotate and scroll/pinch zoom for free. Known bug: changing `cameraTarget` mid-orbit-gesture misbehaves ([forum thread 825543](https://developer.apple.com/forums/thread/825543)). A virtual `PerspectiveCamera` entity is the manual alternative.
- Picking and projection: [`RealityViewCameraContent`](https://developer.apple.com/documentation/realitykit/realityviewcameracontent) (macOS 15.0+) conforms to [`RealityCoordinateSpaceProjecting`](https://developer.apple.com/documentation/realitykit/realitycoordinatespaceprojecting) (macOS 15.0+, verified), which provides `hitTest(point:in:query:mask:)`, `entity(at:in:)`, `project(point:to:)`, `ray(through:in:to:)`. That covers click picking, hover (via `onContinuousHover` + `entity(at:in:)`), and projecting marker positions into SwiftUI space. SwiftUI entity gestures also work: [`targetedToEntity(_:)`](https://developer.apple.com/documentation/swiftui/gesture/targetedtoentity(_:)) is macOS 15.0+ (verified; entities need `CollisionComponent` + `InputTargetComponent`).
- Markers: RealityView `attachments` and `ViewAttachmentComponent` are **visionOS-only** ([`RealityViewAttachments`](https://developer.apple.com/documentation/realitykit/realityviewattachments) and [`ViewAttachmentComponent`](https://developer.apple.com/documentation/realitykit/viewattachmentcomponent) both list only visionOS 1.0 in docs JSON). On macOS, markers are small entities ([`BillboardComponent`](https://developer.apple.com/documentation/realitykit/billboardcomponent) is macOS 15.0+, verified) or a SwiftUI overlay positioned via `project(point:to:)` with back-face culling done by a dot product against the camera direction.
- Cross-platform RealityView/ShaderGraph support was announced in WWDC24 [Discover RealityKit APIs for iOS, macOS, and visionOS (10103)](https://developer.apple.com/videos/play/wwdc2024/10103/).

Real constraints: `CustomMaterial` predates RealityView (macOS 12 / ARView era) and Apple's docs never show it inside `RealityView`; forum coverage of that combination on macOS is thin. It should work (same renderer), but this is unverified — the prototype's first job. ShaderGraphMaterial via MaterialX is the documented-on-macOS-15 fallback and its `setParameter` path is the cleaner way to animate sun direction while scrubbing. A plain `PhysicallyBasedMaterial` + `DirectionalLight` cannot do the job alone: emissive night lights would glow on the day side too, so a custom shader is required either way.

## Candidate B: Custom Metal (MTKView)

Nothing here is unknown, only volume. You hand-roll:

- Sphere mesh: `MDLMesh(sphereWithExtent:...)` via ModelIO → `MTKMesh`, or generate lat/long bands (~50 lines). Textures via `MTKTextureLoader`.
- Fragment shader: the day/night blend below, in MSL. Direct translations exist (see next section).
- Camera/arcball: quaternion trackball (Shoemake's arcball) or simple yaw/pitch orbit; you own the projection/view matrices.
- Picking: unproject click → ray-sphere intersection (a closed-form quadratic against the unit sphere; convert hit point to lat/lon with `atan2`/`asin`). Reference implementation: [Picking and Hit-Testing in Metal](https://metalbyexample.com/picking-hit-testing/) with sample repo [metal-by-example/metal-picking](https://github.com/metal-by-example/metal-picking) (MIT, 67 stars, last push 2023-08).
- Markers: either point sprites in Metal, or (simpler) project lat/lon → world → clip → view coordinates on the CPU each frame and lay SwiftUI views over the `MTKView`. Picking markers then becomes plain 2D hit testing.
- Time scrubbing is trivial: sun direction is one uniform, re-rendered every frame.

Hidden costs: resize/HiDPI handling, gesture feel (momentum, zoom-to-cursor), color management (NSScreen colorspace vs texture sRGB), and anti-aliasing setup — each small, together a few days of polish that RealityKit gives away free.

## Day/night terminator shader technique

Canonical technique, identical in every implementation found: compute `float l = dot(normal, sunDirection)` per fragment, blend day and night textures with a `smoothstep` around 0.

- Canonical minimal reference: [WebGL Fundamentals — day vs night Earth QnA](https://webglfundamentals.org/webgl/lessons/webgl-qna-show-a-night-view-vs-a-day-view-on-a-3d-earth-sphere.html) (two samplers, mix by clamped NdotL).
- Twilight band: [vvanhee/earth-wallpaper](https://github.com/vvanhee/earth-wallpaper) (Three.js + GLSL, active 2026-05, license NOASSERTION — study only) uses `smoothstep(-0.03, 0.07, NdotL)`, i.e. a ~0.1-wide band in dot-product space ≈ 6° of arc ≈ the real civil+nautical twilight width ([terminator background](https://en.wikipedia.org/wiki/Terminator_(solar))). It also gates city-light intensity by `1 - dayFactor` so lights never show in daylight, and adds a slight orange tint in the band. All of this is a 15-line MSL function or a small MaterialX graph.
- Physical plausibility only needs the subsolar point: `sunDirection` (unit vector from Earth's center toward the Sun) is `(cos δ · cos λss, sin δ, -cos δ · sin λss)` in a Y-up, Greenwich-at-+X frame, where δ = solar declination and λss = subsolar longitude.

## Sun position (subsolar point) for an arbitrary Date

- [NOAA Solar Calculator — calculation details](https://gml.noaa.gov/grad/solcalc/calcdetails.html): equations based on Meeus, *Astronomical Algorithms*; declination + equation of time; "very good for years 1800–2100", sunrise/sunset within one minute for |lat| ≤ 72°. The published spreadsheet is ~30 lines of Swift. Subsolar point from it: `lat = δ`, `lon = -15·(hoursUTC - 12 + EoT/60)` degrees.
- [USNO Approximate Solar Coordinates](https://aa.usno.navy.mil/faq/sun_approx): the Astronomical Almanac low-precision algorithm; input is just the Julian date; accuracy ~1 arcminute within two centuries of 2000. 1' ≪ 1 pixel of terminator on any window-sized globe.
- Swift packages:
  - [SunKit](https://github.com/SunKit-Swift/SunKit) — Apache-2.0, 176 stars, active (pushed 2026-03). Computes azimuth/elevation, sunrise/sunset per `CLLocation`, all offline. Oriented to observer-relative output, not the subsolar point; you would still derive δ/EoT yourself or misuse an observer at (0, 0).
  - [Timac/SunCalc](https://github.com/Timac/SunCalc) — MIT, 22 stars, pushed 2025-06; Swift port of suncalc.js (moderate, Meeus-derived accuracy). Same observer-relative shape.
  - [ceeK/Solar](https://github.com/ceeK/Solar) — MIT, 615 stars, active (pushed 2026-08). **Sunrise/sunset times only; no sun position.** Not suitable here.
- Recommendation: hand-roll the NOAA equations (~40 lines, one function `subsolarPoint(date:) -> (lat, lon)`), unit-tested against the [NOAA position calculator](https://gml.noaa.gov/grad/solcalc/azel.html). No dependency earns its keep for this.

## Earth textures (all NASA, public domain, credit required by request)

- Day: **Blue Marble Next Generation** (500 m, monthly composites, 2004) — [collection page](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/) / [dataset description](https://neo.gsfc.nasa.gov/view.php?datasetId=BlueMarbleNG). Downloads per month at 5400×2700 and 21600×10800 (JPEG/GeoTIFF) plus 500 m tiles ([topo+bathy download page](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-topography-bathymetry)). Direct URL verified live: `https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/world.topo.bathy.200412.3x21600x10800.jpg` (and `...3x5400x2700.jpg`; swap `200412` for other months). Credit request: "NASA Earth Observatory".
- Night: **Black Marble 2016** (VIIRS, 742 m/px) — [Earth at Night feature](https://www.earthobservatory.nasa.gov/Features/NightLights), [SVS 30876](https://svs.gsfc.nasa.gov/30876/), [product page](https://viirsland.gsfc.nasa.gov/Products/NASA/BlackMarble.html). Direct URLs verified live: `https://eoimages.gsfc.nasa.gov/images/imagerecords/144000/144898/BlackMarble_2016_01deg.jpg` (3600×1800) and `..._3km.jpg` (13500×6750). Credit: NASA Earth Observatory / NASA's Goddard Space Flight Center.
- Clouds: `https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_2048.jpg` (verified live; Blue Marble cloud composite). Probably skip for v1 — static clouds contradict a scrubbing clock.
- Specular/water mask + prettier processed set: [Natural Earth III](https://www.shadedrelief.com/natural3/pages/textures.html) (Tom Patterson; site reachable, textures stated public domain on the site — re-check the exact wording before shipping).
- Licensing umbrella: [NASA Images and Media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) — NASA content is generally not copyrighted; attribution requested, no NASA endorsement implied.
- Practical limit: Metal's max 2D texture dimension is 16384 on modern Apple GPUs, so the 21600×10800 file must be downsampled to ≤16384×8192 (still overkill for a window-sized globe; 8192×4096 is the sweet spot) or split into tiles.

## Existing open-source Swift globes

| Repo | Stack | License | Last push | Notes |
|---|---|---|---|---|
| [dmojdehi/SwiftGlobe](https://github.com/dmojdehi/SwiftGlobe) | SceneKit, macOS/iOS/tvOS | **none** | 2023-06 | Closest prior art: city lights on dark side via shader modifier, seasonal tilt from day-of-year, glowing markers, pan/zoom. Study only — no license means no reuse. |
| [rwarrender/scenekit-earth](https://github.com/rwarrender/scenekit-earth) | SceneKit playground | none | 2018-09 | Tilt, clouds, night cities. Study only. |
| [Thinkr1/Earthquakes](https://github.com/Thinkr1/Earthquakes) | macOS 3D globe | MIT | 2025-10 | USGS quakes on an interactive globe; recent macOS-native example. |
| [brianadvent/Interactive3DEarth](https://github.com/brianadvent/Interactive3DEarth) | SceneKit tutorial | none | 2017-12 | Basic textured globe. |
| [metal-by-example/metal-picking](https://github.com/metal-by-example/metal-picking) | Metal | MIT | 2023-08 | Ray-sphere picking scaffold, reusable. |
| [vvanhee/earth-wallpaper](https://github.com/vvanhee/earth-wallpaper) | Three.js/GLSL | NOASSERTION | 2026-05 | Best terminator shader reference; translate, don't copy. |

No maintained RealityKit globe was found (GitHub search across `globe earth language:swift`, the [Awesome-RealityKit list](https://divalue.github.io/Awesome-RealityKit/), and topic pages). Whatever we build, the RealityKit path is unpaved.

## SceneKit deprecation

- Apple's docs JSON marks the entire SceneKit framework `deprecatedAt: 26.0` on every platform (macOS introduced 10.8, deprecated 26.0) — [SceneKit docs](https://developer.apple.com/documentation/scenekit).
- WWDC25 session 288, [Bring your SceneKit project to RealityKit](https://developer.apple.com/videos/play/wwdc2025/288/), announced maintenance mode: critical bug fixes only, no new features, migrate to RealityKit. Apple engineers on the forums add there is no removal date and ample notice would precede one ([thread 795520](https://developer.apple.com/forums/thread/795520)).
- Meaning for a new app in 2026: SceneKit still compiles, runs, and will for years, but every new API build-out (SwiftUI integration, new Metal features) lands in RealityKit only, and Xcode flags deprecation warnings. Starting a new app on it is a knowing bet against the platform. Genuinely off the table here, since RealityKit on macOS 15 covers everything SceneKit would have given us, and SwiftGlobe remains available as a conceptual reference.

## Other options considered

- **MapKit**: no public 3D-globe API. `MKMapView` zooms out to a globe only in flyover map types, with no control over lighting, no terminator, no arbitrary-time sun ([forum 101479](https://developer.apple.com/forums/thread/101479), [forum 760542](https://developer.apple.com/forums/thread/760542)). Not viable.
- **SwiftUI Canvas 2.5D fake globe** (orthographic projection drawn per frame): feasible for a flat stylized look but re-implements texture mapping on the CPU; worse than Metal in every dimension except setup. Not pursued.
- No commercial-quality open Swift globe library exists (unlike Web's CesiumJS/three-globe). The Web ecosystem is where the reference shaders live; the Swift ecosystem only has small samples.

## Verdict

**RealityKit first.** Everything the app needs is verified present on macOS 15: RealityView, orbit/zoom camera controls, `hitTest`/`entity(at:)`/`project(point:to:)` for picking-hover-markers, `BillboardComponent`, and two independent routes to a custom terminator material (`CustomMaterial` since macOS 12; `ShaderGraphMaterial` from raw MaterialX data since macOS 15, no Reality Composer Pro needed). The Metal path has zero unknowns but re-implements camera feel, picking, projection, AA, and HiDPI plumbing that RealityKit ships. Keep Metal as the documented fallback; the fragment shader and sun math transfer unchanged.

1–2 day spike, RealityKit: (1) sphere `ModelEntity` in a `RealityView` with `.realityViewCameraControls(.orbit)`; (2) apply an unlit `CustomMaterial` with day+night textures and a sun-direction `custom.vector`, update it per frame from a scrubbed `Date` — this is the go/no-go gate; (3) if CustomMaterial misbehaves under RealityView, retry as MaterialX `ShaderGraphMaterial` with `setParameter`; (4) one marker entity with `CollisionComponent` + `targetedToEntity` tap, plus a SwiftUI label via `project(point:to:)`; (5) measure material-reassignment cost at 60/120 Hz scrubbing.

Spike, Metal (only if step 2–3 both fail): MTKView + MDLMesh sphere + the WebGL-fundamentals shader in MSL, orbit camera, ray-sphere pick. Verify gesture feel and marker overlay effort — the risk is polish time, not feasibility.

Riskiest unknown per approach:
- RealityKit: whether `CustomMaterial` (or MaterialX-loaded `ShaderGraphMaterial`) renders and animates correctly inside `RealityView` on macOS 15 at scrub rates — documented availability, undocumented combination, no prior art found.
- Metal: no single unknown; the risk is diffuse — hand-rolled interaction quality (inertia, zoom-to-cursor, hover latency) eating days of tuning that the report above cannot de-risk in advance.
