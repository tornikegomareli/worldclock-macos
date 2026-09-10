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
    private let state: GlobeState

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
    var isPointerOverGlobe = false
    private var inspectionMarker: ModelEntity?

    init(engine: TimeEngine, store: LocationsStore, state: GlobeState) {
        self.engine = engine
        self.store = store
        self.state = state
    }

    @MainActor
    struct Resources {
        let surface: CustomMaterial
        let atmosphere: CustomMaterial
        let globeMesh: MeshResource
        let haloMesh: MeshResource
    }

    private var preparationTask: Task<Resources, Error>?

    /// Start before World View is requested; simultaneous opens share this work.
    func prewarm() {
        Task(priority: .utility) { try? await prepareResources() }
    }

    func prepareResources() async throws -> Resources {
        if let preparationTask { return try await preparationTask.value }
        let task = Task { try await Self.loadResources() }
        preparationTask = task
        do {
            return try await task.value
        } catch {
            // A failed prewarm must not prevent a later opening from retrying.
            preparationTask = nil
            throw error
        }
    }

    private static func loadResources() async throws -> Resources {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary()
        else { throw GlobeError.metalUnavailable }

        let surfaceShader = CustomMaterial.SurfaceShader(named: "globeSurface", in: library)
        var material = try CustomMaterial(surfaceShader: surfaceShader, lightingModel: .unlit)
        material.emissiveColor.texture = .init(try await Self.loadTexture("earth-night", "jpg", semantic: .color))
        material.custom.texture = .init(try await Self.loadTexture("water-mask", "png", semantic: .raw))
        // Spare scalar slot carries linear elevation data for stylized relief.
        material.roughness.texture = .init(try await Self.loadTexture("earth-elevation", "jpg", semantic: .raw))
        material.custom.value = SIMD4(1, 0, 0, 0)

        let atmosphereShader = CustomMaterial.SurfaceShader(named: "atmosphereSurface", in: library)
        var atmosphere = try CustomMaterial(surfaceShader: atmosphereShader, lightingModel: .unlit)
        atmosphere.blending = .transparent(opacity: 1.0)
        atmosphere.faceCulling = .back
        atmosphere.custom.value = SIMD4(1, 0, 0, 0)
        return Resources(
            surface: material, atmosphere: atmosphere,
            globeMesh: .generateSphere(radius: 1), haloMesh: .generateSphere(radius: 1.012)
        )
    }

    func build(in content: RealityViewCameraContent) async throws {
        let resources = try await prepareResources()
        try Task.checkCancellation()
        let material = resources.surface
        let atmosphere = resources.atmosphere
        let globe = ModelEntity(mesh: resources.globeMesh, materials: [material])
        globe.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
        globe.components.set(InputTargetComponent())
        content.add(globe)
        let halo = ModelEntity(mesh: resources.haloMesh, materials: [atmosphere])
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
        if self.camera == nil, let home = store.home,
           let latitude = home.latitude, let longitude = home.longitude {
            let angles = GlobeMath.cameraAngles(latitude: latitude, longitude: longitude)
            yaw = angles.yaw
            pitch = angles.pitch
        }
        self.camera = camera
        inspectionMarker = nil
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
        if let inspectionMarker {
            inspectionMarker.isEnabled = simd_dot(simd_normalize(inspectionMarker.position), cameraDirection) > 0.05
        }
    }

    func markInspection(_ inspection: GlobeInspection?) {
        inspectionMarker?.removeFromParent()
        inspectionMarker = nil
        guard let inspection, let globe else { return }
        let marker = ModelEntity(
            mesh: .generateSphere(radius: 0.018),
            materials: [UnlitMaterial(color: .systemOrange)]
        )
        marker.position = GlobeMath.unitPosition(latitude: inspection.latitude, longitude: inspection.longitude) * 1.015
        globe.addChild(marker)
        inspectionMarker = marker
        updateMarkerVisibility()
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

    /// A cancellable departure, rotation, and approach, timed independently of frame rate.
    func fly(toLatitude latitude: Double, longitude: Double, animated: Bool = true) {
        cancelFlight()
        dragStart = nil
        magnifyStartDistance = nil
        let target = GlobeMath.cameraAngles(latitude: latitude, longitude: longitude)
        let start = (yaw: yaw, pitch: pitch, distance: distance)
        let duration = GlobeMath.flightDuration(from: start, to: target)
        guard animated, duration > 0 else {
            (yaw, pitch, distance) = GlobeMath.flightPose(from: start, to: target, progress: 1)
            positionCamera()
            state.hasArrived = true
            return
        }
        state.isFlying = true
        flyTask = Task { @MainActor [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while true {
                guard let self, !Task.isCancelled else { return }
                let t = min((ProcessInfo.processInfo.systemUptime - started) / duration, 1)
                (yaw, pitch, distance) = GlobeMath.flightPose(from: start, to: target, progress: t)
                positionCamera()
                if t >= 1 {
                    state.isFlying = false
                    state.hasArrived = true
                    flyTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    // MARK: Camera

    func orbit(by translation: CGSize) {
        cancelFlight()
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
        cancelFlight()
        let start = magnifyStartDistance ?? distance
        magnifyStartDistance = start
        distance = min(max(start / Double(magnification), 1.3), 8)
        positionCamera()
    }

    func endMagnify() {
        magnifyStartDistance = nil
    }

    func cancelFlight() {
        flyTask?.cancel()
        flyTask = nil
        state.isFlying = false
        state.hasArrived = false
    }

    func zoom(by factor: Double) {
        cancelFlight()
        distance = min(max(distance * factor, 1.3), 8)
        positionCamera()
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
            guard let self, self.isPointerOverGlobe else { return event }
            MainActor.assumeIsolated {
                let delta = Double(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8)
                self.zoom(by: 1 - delta * 0.005)
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
    ) async throws -> TextureResource {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw GlobeError.missingTexture(name)
        }
        return try await TextureResource(contentsOf: url, options: .init(semantic: semantic))
    }

    enum GlobeError: Error {
        case metalUnavailable
        case missingTexture(String)
    }
}
