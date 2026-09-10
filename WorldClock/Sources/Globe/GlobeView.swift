import RealityKit
import SwiftUI

/// The Globe and its city search share the Panel's Global Instant.
struct GlobeView: View {
    let controller: GlobeSceneController
    let engine: TimeEngine
    let store: LocationsStore
    let settings: SettingsStore
    let databaseLoader: CityDatabaseLoader
    @Bindable var state: GlobeState
    let theme: PanelTheme
    let onAddCity: (City) -> Void
    let onClose: () -> Void

    @State private var setupError: String?
    @State private var hoverLabel: (text: String, position: CGPoint)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animatesFlight: Bool { !reduceMotion && !settings.prefersCrossfade }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            stage
            footer
                .opacity(state.isFlying ? 0 : 1)
                .offset(y: state.isFlying && animatesFlight ? 10 : 0)
                .animation(settings.animation(.easeOut(duration: state.isFlying ? 0.12 : 0.32)), value: state.isFlying)
                .allowsHitTesting(!state.isFlying)
                .accessibilityHidden(state.isFlying)
        }
        .onChange(of: state.inspection) {
            controller.markInspection(state.inspection)
            if state.inspection == nil { controller.cancelFlight() }
        }
        .onChange(of: state.isJumping) {
            hoverLabel = nil
            controller.isPointerOverGlobe = false
            if state.isJumping {
                controller.removeScrollZoomMonitor()
            } else {
                controller.installScrollZoomMonitor()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .help("Back to locations (Space)")
            .accessibilityLabel("Back to locations")
            Button { state.isJumping = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Jump to a city")
                    Spacer()
                    Text("J").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.pill, in: RoundedRectangle(cornerRadius: 4))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(theme.pill, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Jump to a city")
            .help("Search cities, countries, or UTC offsets (J)")
            Button {
                if let home = store.home { jump(to: GlobeInspection(location: home)) }
            } label: {
                Image(systemName: "house")
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(store.home?.latitude == nil || store.home?.longitude == nil)
            .help("Show Home on the globe")
            .accessibilityLabel("Show Home on the globe")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var stage: some View {
        ZStack(alignment: .top) {
            RealityView { content in
                do {
                    try await controller.build(in: content)
                    controller.markInspection(state.inspection)
                    if let inspection = state.inspection {
                        controller.fly(toLatitude: inspection.latitude, longitude: inspection.longitude, animated: animatesFlight)
                    }
                } catch is CancellationError {
                    // Closing during preparation must not show a setup failure.
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
            .onTapGesture { point in inspect(controller.pick(at: point)) }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    controller.isPointerOverGlobe = !state.isJumping
                    let id = controller.markerID(at: point)
                    controller.highlightMarker(id)
                    if let id, let location = store.locations.first(where: { $0.id == id }) {
                        hoverLabel = (location.cityName, CGPoint(x: point.x, y: max(point.y - 22, 14)))
                    } else {
                        hoverLabel = nil
                    }
                case .ended:
                    controller.isPointerOverGlobe = false
                    controller.highlightMarker(nil)
                    hoverLabel = nil
                }
            }
            .allowsHitTesting(!state.isJumping)
            .onAppear { controller.installScrollZoomMonitor() }
            .onDisappear {
                controller.isPointerOverGlobe = false
                controller.removeScrollZoomMonitor()
                controller.cancelFlight()
            }
            .accessibilityLabel("Interactive world globe")
            .accessibilityHint("Use Jump to a city to explore a location with the keyboard.")

            if let hoverLabel, !state.isJumping {
                Text(hoverLabel.text)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.8), in: Capsule())
                    .foregroundStyle(.white)
                    .position(hoverLabel.position)
                    .allowsHitTesting(false)
            }
            if state.isJumping {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { state.cancelJump() }
                jumpOverlay.padding(16)
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Text("Drag to rotate · Scroll to zoom")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        HStack(spacing: 0) {
                            zoomButton("minus", label: "Zoom out", factor: 1.2)
                            zoomButton("plus", label: "Zoom in", factor: 1 / 1.2)
                        }
                        .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                .padding(12)
            }
            if setupError != nil && !state.isJumping {
                VStack(spacing: 8) {
                    Image(systemName: "globe").font(.largeTitle)
                    Text("The globe couldn’t load").font(.headline)
                    Text("You can still search cities and compare their local times.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .overlay { arrivalOverlay }
        .background(.black)
        .clipped()
    }

    private var arrivalOverlay: some View {
        ZStack {
            if state.hasArrived, !state.isJumping, let inspection = state.inspection {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [.orange.opacity(0.32), .orange.opacity(0)],
                            center: .center, startRadius: 4, endRadius: 34
                        ))
                        .frame(width: 68, height: 68)
                    Circle()
                        .stroke(.orange.opacity(0.35), lineWidth: 0.5)
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(.orange.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .shadow(color: .orange.opacity(0.45), radius: 5)
                }
                .transition(animatesFlight ? .scale(scale: 0.55).combined(with: .opacity) : .opacity)
                VStack(spacing: 3) {
                    Text(inspection.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(TimeFormatting.timeString(
                        LocalTime(of: engine.globalInstant, in: inspection.timeZone),
                        clockFormat: settings.resolvedClockFormat
                    ))
                    .font(.system(size: 12))
                    .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 240)
                .offset(y: 52)
                .transition(.opacity)
            }
        }
        .animation(settings.animation(.easeOut(duration: 0.35)), value: state.hasArrived)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func zoomButton(_ symbol: String, label: String, factor: Double) -> some View {
        Button { controller.zoom(by: factor) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func inspect(_ pick: GlobeSceneController.PickResult) {
        switch pick {
        case let .marker(id):
            if let location = store.locations.first(where: { $0.id == id }) {
                jump(to: GlobeInspection(location: location))
            }
        case let .surface(latitude, longitude):
            if let city = databaseLoader.database?.nearestCity(
                latitude: latitude, longitude: longitude, withinKilometers: 500
            ) {
                if let inspection = GlobeInspection(city: city, savedLocations: store.locations) {
                    jump(to: inspection)
                }
            } else {
                state.inspection = nil
            }
        case .miss:
            state.inspection = nil
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let inspection = state.inspection ?? store.home.map(GlobeInspection.init(location:)) {
            let instant = engine.globalInstant
            let local = LocalTime(of: instant, in: inspection.timeZone)
            let saved = inspection.savedLocation(in: store.locations)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inspection.name)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                            .help(inspection.name)
                        Text(inspection.countryCode.map(countryName) ?? inspection.timeZone.identifier)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(TimeFormatting.timeString(local, clockFormat: settings.resolvedClockFormat))
                            .font(.system(size: 24, weight: .light))
                            .monospacedDigit()
                            .fixedSize()
                        Text(instant.formatted(Date.FormatStyle(
                            date: .abbreviated, time: .omitted, timeZone: inspection.timeZone
                        )))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(relativeLabel(for: inspection, at: instant))
                            .font(.system(size: 11, weight: .medium))
                        Text(sunLabel(for: inspection, at: instant))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if let city = inspection.addableCity, saved == nil {
                        Button { onAddCity(city) } label: {
                            Label("Add Location", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .foregroundStyle(theme.onAccent)
                                .background(theme.accent, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    } else if let saved {
                        Label(inspection.isHome(store.home) ? "Home" : saved.cityName == inspection.name ? "Saved" : "Time zone saved", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .help("Saved as \(saved.cityName)")
                    }
                }
            }
            .padding(16)
        }
    }

    private func relativeLabel(for inspection: GlobeInspection, at instant: Date) -> String {
        let utc = TimeFormatting.utcOffset(seconds: inspection.timeZone.secondsFromGMT(for: instant))
        if inspection.isHome(store.home) { return "Home · \(utc)" }
        let offset = RelativeOffset(of: inspection.timeZone, home: store.home?.timeZone ?? .current, at: instant).seconds
        let relative = offset == 0 ? "Same time as Home" : TimeFormatting.relativeOffset(seconds: offset) + " from Home"
        return "\(relative) · \(utc)"
    }

    private func sunLabel(for inspection: GlobeInspection, at instant: Date) -> String {
        let location = Location(cityName: inspection.name, timeZone: inspection.timeZone,
                                latitude: inspection.latitude, longitude: inspection.longitude)
        switch DayLineModel.sunDay(for: location, at: instant) {
        case let .risesAndSets(_, sunrise, sunset, _):
            let nextIsSunrise = instant < sunrise
            let event = nextIsSunrise ? sunrise : sunset
            return (nextIsSunrise ? "Sunrise " : "Sunset ") + TimeFormatting.timeString(
                LocalTime(of: event, in: inspection.timeZone), clockFormat: settings.resolvedClockFormat
            )
        case .polarDay: return "Midnight sun"
        case .polarNight: return "Polar night"
        case .twilightOnly: return "Sun stays below the horizon"
        }
    }

    private var jumpResults: [GlobeInspection] {
        if state.jumpQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.locations.filter { $0.latitude != nil && $0.longitude != nil }
                .map(GlobeInspection.init(location:))
        }
        return databaseLoader.database?.search(state.jumpQuery, at: engine.globalInstant, limit: 5)
            .compactMap { GlobeInspection(city: $0, savedLocations: store.locations) } ?? []
    }

    private var jumpOverlay: some View {
        let results = jumpResults
        let selected = min(state.jumpSelection, max(results.count - 1, 0))
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                FocusedTextField(
                    placeholder: "City, country, or UTC offset",
                    text: $state.jumpQuery,
                    onSubmit: {
                        if results.indices.contains(selected) { jump(to: results[selected]) }
                    },
                    onCancel: { state.cancelJump() },
                    onMoveUp: { state.jumpSelection = PanelKeyLogic.movedResultSelection(from: selected, by: -1, count: results.count) },
                    onMoveDown: { state.jumpSelection = PanelKeyLogic.movedResultSelection(from: selected, by: 1, count: results.count) }
                )
                Button { state.cancelJump() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(theme.pill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close city search")
                .help("Close search (Esc)")
            }
            .padding(14)
            Divider().overlay(theme.separator)
            if results.isEmpty {
                VStack(spacing: 6) {
                    Text(databaseLoader.database == nil ? "Loading cities…" : "No cities found")
                        .font(.system(size: 13, weight: .medium))
                    Text("Try a city name, country, or UTC+9.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                Text(state.jumpQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "YOUR LOCATIONS" : "CITIES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
                                jumpRow(place, selected: index == selected)
                                    .id(place.id)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(results.count, 5)) * 50)
                    .onChange(of: state.jumpSelection) { proxy.scrollTo(results[selected].id) }
                    .onChange(of: state.jumpQuery) { proxy.scrollTo(results[0].id, anchor: .top) }
                }
            }
            HStack {
                Text("↑ ↓ to choose")
                Text("↵ to jump")
                Spacer()
                Text("esc to close")
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.secondaryText)
            .padding(12)
        }
        .foregroundStyle(theme.text)
        .background {
            RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 14).fill(theme.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onChange(of: state.jumpQuery) { state.jumpSelection = 0 }
    }

    private func jumpRow(_ place: GlobeInspection, selected: Bool) -> some View {
        Button { jump(to: place) } label: {
            HStack(spacing: 10) {
                Image(systemName: place.isHome(store.home) ? "house" : "mappin.and.ellipse")
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).font(.system(size: 13, weight: .medium))
                    Text(place.countryCode.map(countryName) ?? place.timeZone.identifier)
                        .font(.system(size: 11)).foregroundStyle(theme.secondaryText)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Text(TimeFormatting.timeString(LocalTime(of: engine.globalInstant, in: place.timeZone),
                                               clockFormat: settings.resolvedClockFormat))
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                Image(systemName: "return").font(.system(size: 10))
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(selected ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .padding(.horizontal, 6)
    }

    private func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private func jump(to place: GlobeInspection) {
        state.cancelJump()
        state.inspection = place
        controller.fly(toLatitude: place.latitude, longitude: place.longitude, animated: animatesFlight)
    }
}
