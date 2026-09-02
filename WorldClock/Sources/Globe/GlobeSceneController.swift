import AppKit
import Metal
import Observation
import RealityKit
import simd
import SwiftUI

/// Owns the Globe's RealityKit scene: the Earth sphere with the terminator
/// material, the atmosphere shell, and the manual orbit/zoom camera (ADR-0002
/// spike finding: RealityKit's built-in camera controls aren't usable).
/// The sun direction always renders the shared Global Instant (ADR-0001).
@MainActor
final class GlobeSceneController {
    private let engine: TimeEngine

    private var globe: ModelEntity?
    private var halo: ModelEntity?
    private var material: CustomMaterial?
    private var atmosphereMaterial: CustomMaterial?
    private var content: RealityViewCameraContent?
    private var camera: PerspectiveCamera?

    // Spherical camera coordinates.
    private var yaw = 0.0
    private var pitch = 0.35
    private var distance = 2.6
    private var dragStart: (yaw: Double, pitch: Double)?
    private var magnifyStartDistance: Double?
    private var scrollMonitor: Any?

    init(engine: TimeEngine) {
        self.engine = engine
    }

    func build(in content: RealityViewCameraContent) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary()
        else { throw GlobeError.metalUnavailable }

        let surfaceShader = CustomMaterial.SurfaceShader(named: "globeSurface", in: library)
        var material = try CustomMaterial(surfaceShader: surfaceShader, lightingModel: .unlit)
        material.baseColor.texture = .init(try Self.loadTexture("earth-day", "jpg", semantic: .color))
        material.emissiveColor.texture = .init(try Self.loadTexture("earth-night", "jpg", semantic: .color))
        material.custom.texture = .init(try Self.loadTexture("water-mask", "png", semantic: .raw))
        material.custom.value = SIMD4(1, 0, 0, 0)

        let globe = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        globe.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
        globe.components.set(InputTargetComponent())
        content.add(globe)

        let atmosphereShader = CustomMaterial.SurfaceShader(named: "atmosphereSurface", in: library)
        var atmosphere = try CustomMaterial(surfaceShader: atmosphereShader, lightingModel: .unlit)
        atmosphere.blending = .transparent(opacity: 1.0)
        atmosphere.faceCulling = .back
        atmosphere.custom.value = SIMD4(1, 0, 0, 0)
        let halo = ModelEntity(mesh: .generateSphere(radius: 1.04), materials: [atmosphere])
        globe.addChild(halo)

        let camera = PerspectiveCamera()
        content.add(camera)

        self.globe = globe
        self.halo = halo
        self.material = material
        self.atmosphereMaterial = atmosphere
        self.content = content
        self.camera = camera
        positionCamera()
        trackGlobalInstant()
    }

    /// Re-renders the sun for every Global Instant change — ticking and
    /// scrubbing alike — via observation tracking.
    private func trackGlobalInstant() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            updateSun(for: engine.globalInstant)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackGlobalInstant() }
        }
    }

    private func updateSun(for instant: Date) {
        guard var material, let globe else { return }
        let direction = GlobeMath.sunDirection(at: instant)
        let vector = SIMD4(direction.x, direction.y, direction.z, 0)
        material.custom.value = vector
        globe.model?.materials = [material]
        self.material = material
        if var atmosphereMaterial, let halo {
            atmosphereMaterial.custom.value = vector
            halo.model?.materials = [atmosphereMaterial]
            self.atmosphereMaterial = atmosphereMaterial
        }
    }

    // MARK: Camera

    func orbit(by translation: CGSize) {
        let start = dragStart ?? (yaw, pitch)
        dragStart = start
        yaw = start.yaw - Double(translation.width) * 0.006
        pitch = min(max(start.pitch + Double(translation.height) * 0.006, -1.45), 1.45)
        positionCamera()
    }

    func endOrbit() {
        dragStart = nil
    }

    func magnify(to magnification: CGFloat) {
        let start = magnifyStartDistance ?? distance
        magnifyStartDistance = start
        distance = min(max(start / Double(magnification), 1.3), 8)
        positionCamera()
    }

    func endMagnify() {
        magnifyStartDistance = nil
    }

    func removeScrollZoomMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    func installScrollZoomMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
                self.distance = min(max(self.distance * (1 - delta * 0.005), 1.3), 8)
                self.positionCamera()
            }
            return event
        }
    }

    private func positionCamera() {
        guard let camera else { return }
        camera.position = [
            Float(distance * cos(pitch) * sin(yaw)),
            Float(distance * sin(pitch)),
            Float(distance * cos(pitch) * cos(yaw)),
        ]
        camera.look(at: .zero, from: camera.position, relativeTo: nil)
    }

    private static func loadTexture(
        _ name: String, _ ext: String, semantic: TextureResource.Semantic
    ) throws -> TextureResource {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw GlobeError.missingTexture(name)
        }
        return try TextureResource.load(contentsOf: url, options: .init(semantic: semantic))
    }

    enum GlobeError: Error {
        case metalUnavailable
        case missingTexture(String)
    }
}
