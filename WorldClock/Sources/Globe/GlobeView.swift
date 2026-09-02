import RealityKit
import SwiftUI

/// The Globe: the expanded 3D surface rendering the same Global Instant as
/// the Panel, including its sunlight terminator (CONTEXT.md). Saved
/// Locations appear as markers; clicking anywhere inspects the nearest City;
/// J opens Jump.
struct GlobeView: View {
    let controller: GlobeSceneController
    let engine: TimeEngine
    let store: LocationsStore
    let settings: SettingsStore
    let databaseLoader: CityDatabaseLoader
    @Bindable var state: GlobeState
    /// Adds a City to the Location list (⌘K's add path — persists + animates).
    let onAddCity: (City) -> Void

    @State private var setupError: String?
    @State private var hoverLabel: (text: String, position: CGPoint)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RealityView { content in
                do {
                    try controller.build(in: content)
                } catch {
                    setupError = "\(error)"
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in controller.orbit(by: value.translation) }
                    .onEnded { _ in controller.endOrbit() }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in controller.magnify(to: value.magnification) }
                    .onEnded { _ in controller.endMagnify() }
            )
            .onTapGesture { point in
                inspect(controller.pick(at: point))
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    let id = controller.markerID(at: point)
                    state.hoveredLocationID = id
                    controller.highlightMarker(id)
                    if let id, let location = store.locations.first(where: { $0.id == id }) {
                        hoverLabel = (location.cityName, CGPoint(x: point.x, y: point.y - 18))
                    } else {
                        hoverLabel = nil
                    }
                case .ended:
                    state.hoveredLocationID = nil
                    controller.highlightMarker(nil)
                    hoverLabel = nil
                }
            }
            .onAppear { controller.installScrollZoomMonitor() }

            if let inspection = state.inspection {
                inspectorCard(for: inspection)
                    .padding(14)
            }

            if state.isJumping {
                jumpOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if let hoverLabel {
                Text(hoverLabel.text)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .position(hoverLabel.position)
                    .allowsHitTesting(false)
            }

            if let setupError {
                Text(setupError)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.black.opacity(0.8))
            }
        }
        .background(.black)
    }

    // MARK: Picking → inspection

    private func inspect(_ pick: GlobeSceneController.PickResult) {
        switch pick {
        case let .marker(id):
            if let location = store.locations.first(where: { $0.id == id }) {
                state.inspection = GlobeInspection(location: location)
            }
        case let .surface(latitude, longitude):
            if let city = databaseLoader.database?.nearestCity(
                latitude: latitude, longitude: longitude, withinKilometers: 500
            ) {
                state.inspection = GlobeInspection(city: city, savedLocations: store.locations)
            } else {
                state.inspection = nil
            }
        case .miss:
            state.inspection = nil
        }
    }

    // MARK: Inspector

    private func inspectorCard(for inspection: GlobeInspection) -> some View {
        let instant = engine.globalInstant
        let localTime = LocalTime(of: instant, in: inspection.timeZone)
        let utc = TimeFormatting.utcOffset(seconds: inspection.timeZone.secondsFromGMT(for: instant))
        let homeZone = store.home?.timeZone ?? inspection.timeZone
        let relative = TimeFormatting.relativeOffset(
            seconds: RelativeOffset(of: inspection.timeZone, home: homeZone, at: instant).seconds
        )
        let sunset: String? = {
            let probe = Location(
                cityName: inspection.name, timeZone: inspection.timeZone,
                latitude: inspection.latitude, longitude: inspection.longitude
            )
            guard case let .risesAndSets(_, _, sunsetDate, _) = DayLineModel.sunDay(for: probe, at: instant) else {
                return nil
            }
            return TimeFormatting.timeString(
                LocalTime(of: sunsetDate, in: inspection.timeZone),
                clockFormat: settings.resolvedClockFormat
            )
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(inspection.name)
                .font(.title3.weight(.semibold))
            Text(TimeFormatting.timeString(localTime, clockFormat: settings.resolvedClockFormat))
                .font(.system(size: 28, weight: .light).monospacedDigit())
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("Offset").foregroundStyle(.secondary)
                    Text("\(relative) · \(utc)")
                }
                if let sunset {
                    GridRow {
                        Text("Sunset").foregroundStyle(.secondary)
                        Text(sunset)
                    }
                }
            }
            .font(.callout)
            if let city = inspection.addableCity {
                Button("Add to Clocks") { onAddCity(city) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(minWidth: 190, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.primary)
    }

    // MARK: Jump

    private var jumpResults: [City] {
        guard let database = databaseLoader.database else { return [] }
        return database.search(state.jumpQuery, at: engine.globalInstant, limit: 6)
    }

    private var jumpOverlay: some View {
        VStack(spacing: 0) {
            FocusedTextField(
                placeholder: "Jump to city…",
                text: $state.jumpQuery,
                onSubmit: {
                    if let first = jumpResults.first { jump(to: first) }
                },
                onCancel: { state.cancelJump() }
            )
            .padding(10)
            ForEach(jumpResults.prefix(5)) { city in
                Button {
                    jump(to: city)
                } label: {
                    HStack {
                        Text(city.name)
                        Spacer()
                        Text(city.country).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 40)
    }

    private func jump(to city: City) {
        state.cancelJump()
        controller.fly(toLatitude: city.latitude, longitude: city.longitude)
        state.inspection = GlobeInspection(city: city, savedLocations: store.locations)
    }
}
