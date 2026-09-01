import Metal
import RealityKit
import SwiftUI

/// The spike scene: a unit-sphere Earth with the CustomMaterial terminator,
/// orbit camera controls, a Date scrubber driving the sun direction, and
/// click → lat/lon picking.
struct GlobeSpikeView: View {
    @State private var scene = GlobeScene()
    /// Hours away from now; ±7 days like the Panel's scrub range.
    @State private var hoursOffset: Double = Self.launchHoursOffset
    @State private var animating = false
    @State private var pickReadout = "Click the globe to pick a coordinate"
    @State private var setupError: String?

    /// "-spikeHoursOffset N" pins the terminator for reproducible screenshots.
    private static var launchHoursOffset: Double {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-spikeHoursOffset"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1),
              let value = Double(ProcessInfo.processInfo.arguments[index + 1])
        else { return 0 }
        return value
    }

    private var simulatedDate: Date {
        Date().addingTimeInterval(hoursOffset * 3600)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RealityView { content in
                    do {
                        try scene.build(in: content)
                        scene.updateSun(for: simulatedDate)
                    } catch {
                        setupError = "\(error)"
                    }
                }
                .realityViewCameraControls(.orbit)
                .onTapGesture { point in
                    if let coordinate = scene.pick(at: point) {
                        pickReadout = String(
                            format: "Picked: %.2f°, %.2f°", coordinate.latitude, coordinate.longitude
                        )
                    }
                }
                if let setupError {
                    Text(setupError)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.black.opacity(0.8))
                }
            }

            controls
        }
        .background(.black)
        .onChange(of: hoursOffset) { scene.updateSun(for: simulatedDate) }
        .task(id: animating) {
            // Scrub-rate stress: advance the sun every frame while animating.
            while animating, !Task.isCancelled {
                hoursOffset += 0.5
                if hoursOffset > 168 { hoursOffset = -168 }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(simulatedDate.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
                Spacer()
                Text(pickReadout)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Animate", isOn: $animating)
                Text(String(format: "%.1f ms/update", scene.lastUpdateMilliseconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $hoursOffset, in: -168...168) {
                Text("±7 days")
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

/// Owns the RealityKit entities and the CustomMaterial whose sun-direction
/// uniform the scrubber drives.
@MainActor
@Observable
final class GlobeScene {
    private var globe: ModelEntity?
    private var material: CustomMaterial?
    private var content: RealityViewCameraContent?
    private(set) var lastUpdateMilliseconds = 0.0

    struct Coordinate {
        let latitude: Double
        let longitude: Double
    }

    func build(in content: RealityViewCameraContent) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary()
        else { throw SpikeError.noMetal }

        let surfaceShader = CustomMaterial.SurfaceShader(named: "globeSurface", in: library)
        var material = try CustomMaterial(surfaceShader: surfaceShader, lightingModel: .unlit)
        material.baseColor.texture = .init(try TextureResource.load(named: "earth-day"))
        material.emissiveColor.texture = .init(try TextureResource.load(named: "earth-night"))
        material.custom.value = SIMD4(1, 0, 0, 0)

        let globe = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        globe.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
        globe.components.set(InputTargetComponent())
        content.add(globe)

        let camera = PerspectiveCamera()
        camera.position = [0, 0, 3]
        content.add(camera)

        self.globe = globe
        self.material = material
        self.content = content
    }

    /// Sun direction from the subsolar point. Empirical finding for #14: the
    /// research doc assumed z = −sin λ, but generateSphere's texture mapping
    /// puts east longitudes on +Z (Greenwich at +X, Y up), so z = +sin λ.
    func updateSun(for date: Date) {
        guard var material, let globe else { return }
        let start = ContinuousClock.now

        let subsolar = Astronomy.subsolarPoint(at: date)
        let latitude = subsolar.latitude * .pi / 180
        let longitude = subsolar.longitude * .pi / 180
        material.custom.value = SIMD4(
            Float(cos(latitude) * cos(longitude)),
            Float(sin(latitude)),
            Float(cos(latitude) * sin(longitude)),
            0
        )
        globe.model?.materials = [material]
        self.material = material

        lastUpdateMilliseconds = Double(start.duration(to: .now).components.attoseconds) / 1e15
    }

    /// Ray-hits the sphere at a view point and converts to lat/lon in the
    /// same frame as the sun vector.
    func pick(at point: CGPoint) -> Coordinate? {
        guard let content, let globe else { return nil }
        guard let hit = content.hitTest(point: point, in: .local).first(where: { $0.entity == globe }) else {
            return nil
        }
        let local = globe.convert(position: hit.position, from: nil)
        let unit = normalize(local)
        let latitude = asin(Double(unit.y)) * 180 / .pi
        let longitude = atan2(Double(unit.z), Double(unit.x)) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    enum SpikeError: Error {
        case noMetal
    }
}
