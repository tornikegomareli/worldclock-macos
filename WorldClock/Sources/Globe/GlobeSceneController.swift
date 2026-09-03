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
    private let store: LocationsStore

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

    init(engine: TimeEngine, store: LocationsStore) {
        self.engine = engine
        self.store = store
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

        // Embedded in the Panel, the RealityView is torn down and rebuilt on
        // every present — old marker entities belong to the previous content.
        markers.removeAll()
        self.globe = globe
        self.halo = halo
        self.material = material
        self.atmosphereMaterial = atmosphere
        self.content = content
        self.camera = camera
        positionCamera()
        updateSun(for: engine.globalInstant)
        syncMarkers(with: store.locations)
        if !isObserving {
            isObserving = true
            trackGlobalInstant()
            trackMarkers()
        }
    }

    /// Observation chains re-arm themselves forever; arm them once, or every
    /// rebuild would add a duplicate chain.
    private var isObserving = false

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

    // MARK: Markers

    private var markers: [Location.ID: ModelEntity] = [:]

    /// Keeps one subtle marker per saved Location, resynced on add/remove.
    private func trackMarkers() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            syncMarkers(with: store.locations)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackMarkers() }
        }
    }

    private func syncMarkers(with locations: [Location]) {
        guard let globe else { return }
        var stale = markers
        for location in locations {
            stale.removeValue(forKey: location.id)
            guard let latitude = location.latitude, let longitude = location.longitude else { continue }
            let position = GlobeMath.unitPosition(latitude: latitude, longitude: longitude) * 1.005
            if let existing = markers[location.id] {
                existing.position = position
                continue
            }
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.012),
                materials: [UnlitMaterial(color: .white)]
            )
            marker.name = location.id
            marker.position = position
            marker.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.03)]))
            marker.components.set(InputTargetComponent())
            globe.addChild(marker)
            markers[location.id] = marker
        }
        for (id, entity) in stale {
            entity.removeFromParent()
            markers.removeValue(forKey: id)
        }
        updateMarkerVisibility()
    }

    /// Far-side markers bleed through the sphere and steal hit tests;
    /// disable everything on the back hemisphere relative to the camera.
    private func updateMarkerVisibility() {
        let cameraDirection = simd_normalize(
            SIMD3(
                Float(cos(pitch) * sin(yaw)),
                Float(sin(pitch)),
                Float(cos(pitch) * cos(yaw))
            )
        )
        for marker in markers.values {
            let facing = simd_dot(simd_normalize(marker.position), cameraDirection)
            marker.isEnabled = facing > 0.05
        }
    }

    /// Hover feedback: the hovered marker grows and warms.
    func highlightMarker(_ id: Location.ID?) {
        for (markerID, marker) in markers {
            let highlighted = markerID == id
            marker.scale = highlighted ? SIMD3(repeating: 1.8) : SIMD3(repeating: 1)
            marker.model?.materials = [
                UnlitMaterial(color: highlighted ? .systemYellow : .white)
            ]
        }
    }

    // MARK: Picking

    enum PickResult {
        case marker(Location.ID)
        case surface(latitude: Double, longitude: Double)
        case miss
    }

    func pick(at point: CGPoint) -> PickResult {
        guard let content, let globe else { return .miss }
        // Only the nearest hit counts: a marker behind the globe must never
        // outrank the surface in front of it.
        let hits = content.hitTest(point: point, in: .local)
        if let nearest = hits.first, markers[nearest.entity.name] != nil {
            return .marker(nearest.entity.name)
        }
        guard let globeHit = hits.first(where: { $0.entity == globe }) else { return .miss }
        let local = globe.convert(position: globeHit.position, from: nil)
        let coordinate = GlobeMath.coordinate(fromUnitPosition: local)
        return .surface(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The marker under the pointer, for hover highlighting.
    func markerID(at point: CGPoint) -> Location.ID? {
        guard let content else { return nil }
        return content.hitTest(point: point, in: .local)
            .first { markers[$0.entity.name] != nil }?
            .entity.name
    }

    // MARK: Jump

    private var flyTask: Task<Void, Never>?

    /// Rotates the camera to face a coordinate along the shortest arc.
    func fly(toLatitude latitude: Double, longitude: Double) {
        let target = GlobeMath.cameraAngles(latitude: latitude, longitude: longitude)
        var deltaYaw = (target.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if deltaYaw > .pi { deltaYaw -= 2 * .pi }
        if deltaYaw < -.pi { deltaYaw += 2 * .pi }
        let startYaw = yaw
        let startPitch = pitch
        let deltaPitch = target.pitch - pitch

        flyTask?.cancel()
        flyTask = Task { @MainActor [weak self] in
            let steps = 40
            for step in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t) // smoothstep
                yaw = startYaw + deltaYaw * eased
                pitch = startPitch + deltaPitch * eased
                positionCamera()
                try? await Task.sleep(for: .milliseconds(14))
            }
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
                let delta = Double(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8)
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
        updateMarkerVisibility()
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
