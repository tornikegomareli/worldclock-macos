import RealityKit
import SwiftUI

/// The Globe, expanded in place of the lanes: the 3D Earth rendering the same
/// Global Instant as the header (CONTEXT.md), over a footer showing the
/// selected place and the Jump affordance. Saved Locations appear as markers;
/// clicking anywhere inspects the nearest City; J opens Jump.
struct GlobeView: View {
    let controller: GlobeSceneController
    let engine: TimeEngine
    let store: LocationsStore
    let settings: SettingsStore
    let databaseLoader: CityDatabaseLoader
    @Bindable var state: GlobeState
    let theme: PanelTheme
    /// Adds a City to the Location list (⌘K's add path — persists + animates).
    let onAddCity: (City) -> Void

    @State private var setupError: String?
    @State private var hoverLabel: (text: String, position: CGPoint)?

    var body: some View {
        VStack(spacing: 0) {
            stage
            footer
        }
    }

    // MARK: Stage

    private var stage: some View {
        ZStack(alignment: .top) {
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
            .onDisappear { controller.removeScrollZoomMonitor() }

            if state.isJumping {
                jumpOverlay
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

    // MARK: Footer — the selected place (inspection, else Home) + Jump

    private var footerInspection: GlobeInspection? {
        state.inspection ?? store.home.map(GlobeInspection.init(location:))
    }

    @ViewBuilder
    private var footer: some View {
        if let inspection = footerInspection {
            let instant = engine.globalInstant
            let localTime = LocalTime(of: instant, in: inspection.timeZone)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(inspection.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(TimeFormatting.timeString(localTime, clockFormat: settings.resolvedClockFormat))
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                    }
                    Text(meta(for: inspection, at: instant))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let city = inspection.addableCity {
                    Button {
                        onAddCity(city)
                    } label: {
                        Text("Add to Clocks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    state.isJumping = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Jump to a city")
                            .font(.system(size: 12, weight: .medium))
                        Text("J")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.separator, lineWidth: 1))
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .frame(height: 28)
                    .background(theme.pill, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
            .overlay(alignment: .top) {
                Rectangle().fill(theme.separator).frame(height: 1)
            }
        }
    }

    /// "Home · UTC−7 · Sunset 7:14", or "+9h from home · UTC+9 · Sunset 17:32".
    private func meta(for inspection: GlobeInspection, at instant: Date) -> String {
        let utc = TimeFormatting.utcOffset(seconds: inspection.timeZone.secondsFromGMT(for: instant))
        let homeZone = store.home?.timeZone ?? inspection.timeZone
        let isHome = inspection.timeZone.identifier == store.home?.id
        let relative: String = if isHome {
            "Home"
        } else {
            TimeFormatting.relativeOffset(
                seconds: RelativeOffset(of: inspection.timeZone, home: homeZone, at: instant).seconds
            ) + " from home"
        }
        var parts = [relative, utc]
        let probe = Location(
            cityName: inspection.name, timeZone: inspection.timeZone,
            latitude: inspection.latitude, longitude: inspection.longitude
        )
        if case let .risesAndSets(_, _, sunset, _) = DayLineModel.sunDay(for: probe, at: instant) {
            let text = TimeFormatting.timeString(
                LocalTime(of: sunset, in: inspection.timeZone),
                clockFormat: settings.resolvedClockFormat
            )
            parts.append("Sunset \(text)")
        }
        return parts.joined(separator: " · ")
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
                        Text(city.country).foregroundStyle(theme.secondaryText)
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
        .padding(.top, 24)
    }

    private func jump(to city: City) {
        state.cancelJump()
        controller.fly(toLatitude: city.latitude, longitude: city.longitude)
        state.inspection = GlobeInspection(city: city, savedLocations: store.locations)
    }
}
