import AppKit
import simd
import SwiftUI

/// Panel content, Meridian layout: an identity header ("It's 5:02 PM here in
/// San Francisco" under a sky wash tracking home's sun), then every Location
/// as a lane on one shared 24-hour home-time axis with a single meridian
/// cursor crossing all lanes at the Global Instant. Dragging any lane scrubs
/// the meridian. The Globe expands in place of the lanes.
struct PanelContentView: View {
    let engine: TimeEngine
    let store: LocationsStore
    @Bindable var state: PanelState
    let databaseLoader: CityDatabaseLoader
    let settings: SettingsStore
    let weatherStore: WeatherStore
    let greetingProvider: GreetingProvider?
    let globeScene: GlobeSceneController
    let globeState: GlobeState
    let onCommand: (PanelCommand) -> Void

    /// The shared column geometry: name | lane | time. The axis labels and
    /// the meridian cursor derive from the same constants, so they align.
    enum Metrics {
        static let nameWidth: CGFloat = 100
        static let timeWidth: CGFloat = 66
        static let leadingPad: CGFloat = 14
        static let trailingPad: CGFloat = 12
        static let columnSpacing: CGFloat = 8
        static let collapsedWidth: CGFloat = 380
        static let globeWidth: CGFloat = 440
        static let globeAreaHeight: CGFloat = 600
        static let overlayHeight: CGFloat = 460
    }

    /// The drag in progress: its frozen anchor day plus the raw/effective
    /// fraction accumulator that implements Shift precision.
    @State private var scrubDrag: (anchor: Date, previousRaw: Double, effective: Double)?

    /// The Location whose offset caption transiently shows both
    /// interpretations after a click.
    @State private var revealedOffsetID: Location.ID?
    @State private var revealResetTask: Task<Void, Never>?

    /// The Location under the pointer; its secondary info shows the Greeting.
    @State private var hoveredLocationID: Location.ID?

    @Environment(\.colorScheme) private var colorScheme

    private var clockFormat: ClockFormat { settings.resolvedClockFormat }
    private var isTimeTravel: Bool { engine.state != .now }
    private var theme: PanelTheme {
        .resolve(dark: colorScheme == .dark, timeTravel: isTimeTravel)
    }
    private var homeZone: TimeZone { store.home?.timeZone ?? .current }

    var body: some View {
        VStack(spacing: 0) {
            if state.isSearching {
                searchOverlay
                    .frame(height: Metrics.overlayHeight)
            } else if state.isCommandSearching {
                commandOverlay
                    .frame(height: Metrics.overlayHeight)
            } else {
                if state.isGlobePresented {
                    globeHeader
                    GlobeView(
                        controller: globeScene, engine: engine, store: store,
                        settings: settings, databaseLoader: databaseLoader,
                        state: globeState, theme: theme,
                        onAddCity: { onCommand(.addLocation($0)) },
                        onClose: { onCommand(.openGlobe) }
                    )
                    .frame(height: Metrics.globeAreaHeight)
                    .transition(.opacity)
                } else {
                    identityHeader
                    axisRow
                    locationsList
                    addLocationFooter
                    if settings.showWeather {
                        Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                            Image("AppleWeather")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 18)
                        }
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityLabel("Current weather from Apple Weather. View data sources.")
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(width: state.isGlobePresented ? Metrics.globeWidth : Metrics.collapsedWidth)
        .foregroundStyle(theme.text)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(theme.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.edge, lineWidth: 0.5))
        .animation(settings.animation(.easeInOut(duration: 0.35)), value: isTimeTravel)
        .animation(settings.animation(.easeInOut(duration: 0.22)), value: state.isGlobePresented)
    }

    // MARK: Identity header

    private var globeHeader: some View {
        HStack {
            Label("World view", systemImage: "globe")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if isTimeTravel {
                Button("Return to Now") { onCommand(.returnToNow) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
            } else {
                Text("\(store.home?.cityName ?? "Home") · \(TimeFormatting.timeString(LocalTime(of: engine.globalInstant, in: homeZone), clockFormat: clockFormat))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var identityHeader: some View {
        let instant = engine.globalInstant
        let local = LocalTime(of: instant, in: homeZone)
        let (time, suffix) = splitTime(local)

        return VStack(spacing: 0) {
            Text(kicker)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Text("It’s")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 6)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(time)
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .tracking(-1.3)
                    .contentTransition(.numericText())
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.top, 2)
            .animation(settings.animation(.easeInOut(duration: 0.2)), value: time)
            HStack(spacing: 3) {
                Text("here in")
                    .foregroundStyle(theme.secondaryText)
                Text(store.home?.cityName ?? "—")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.top, 6)
            wordmark
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if let skyColor {
                LinearGradient(colors: [skyColor, .clear], startPoint: .top, endPoint: .bottom)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if isTimeTravel {
                Button("Now") { onCommand(.returnToNow) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(theme.accent, in: Capsule())
                    .padding(14)
                    .transition(.opacity)
            }
        }
        .animation(settings.animation(.easeInOut(duration: 0.4)), value: skyColor)
    }

    /// "Now · Wed, Sep 3", or "Time Travel · Tomorrow" in the home zone.
    private var kicker: String {
        if isTimeTravel {
            let day = TimeFormatting.relativeDayLabel(
                of: engine.globalInstant, in: homeZone,
                relativeTo: engine.now, in: homeZone
            ) ?? "Today"
            return "Time Travel · \(day)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = homeZone
        formatter.dateFormat = "EEE, MMM d"
        return "Now · \(formatter.string(from: engine.globalInstant))"
    }

    /// WORLD · globe coin · CLOCK. The coin is the Globe toggle (also Space);
    /// it fills with accent while the Globe is open.
    private var wordmark: some View {
        Button {
            onCommand(.openGlobe)
        } label: {
            HStack(spacing: 10) {
                Text("WORLD").tracking(1.8)
                ZStack {
                    if state.isGlobePresented {
                        Circle().fill(theme.accent)
                    } else {
                        Circle().fill(RadialGradient(
                            colors: [
                                Color(red: 120 / 255, green: 170 / 255, blue: 230 / 255, opacity: 0.55),
                                Color(red: 40 / 255, green: 70 / 255, blue: 130 / 255, opacity: 0.35),
                            ],
                            center: UnitPoint(x: 0.36, y: 0.32),
                            startRadius: 0,
                            endRadius: 20
                        ))
                    }
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.isGlobePresented ? theme.onAccent : theme.text)
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(theme.edge, lineWidth: 1))
                Text("CLOCK").tracking(1.8)
            }
            .font(.system(size: 13, weight: .semibold))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isGlobePresented ? "Back to locations" : "Explore the world")
        .help("Open the Globe (Space)")
    }

    /// The header wash from home's real sun altitude: day blue, dusk warm,
    /// night indigo. Suppressed during Time Travel — amber owns the panel.
    private var skyColor: Color? {
        guard !isTimeTravel, let home = store.home,
              let latitude = home.latitude, let longitude = home.longitude
        else { return nil }
        let sun = GlobeMath.sunDirection(at: engine.globalInstant)
        let position = GlobeMath.unitPosition(latitude: latitude, longitude: longitude)
        let altitude = asin(Double(min(max(simd_dot(sun, position), -1), 1))) * 180 / .pi
        if abs(altitude) < 8 { return theme.skyDusk }
        return altitude >= 8 ? theme.skyDay : theme.skyNight
    }

    private func splitTime(_ localTime: LocalTime) -> (time: String, suffix: String?) {
        switch clockFormat {
        case .twentyFourHour:
            return (String(format: "%02d:%02d", localTime.hour, localTime.minute), nil)
        case .twelveHour:
            let hour12 = localTime.hour % 12 == 0 ? 12 : localTime.hour % 12
            return (
                String(format: "%d:%02d", hour12, localTime.minute),
                localTime.hour < 12 ? "AM" : "PM"
            )
        }
    }

    // MARK: Shared axis + lanes

    /// Hour labels over the lane column: 0 · 6 · 12 · 18 · 24, in home time.
    private var axisRow: some View {
        HStack(spacing: Metrics.columnSpacing) {
            Color.clear.frame(width: Metrics.nameWidth, height: 1)
            GeometryReader { geometry in
                ZStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text("\(hour)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.tertiaryText)
                            .position(
                                x: min(max(geometry.size.width * CGFloat(hour) / 24, 5), geometry.size.width - 8),
                                y: geometry.size.height / 2
                            )
                    }
                }
            }
            .frame(height: 14)
            Color.clear.frame(width: Metrics.timeWidth, height: 1)
        }
        .padding(.leading, Metrics.leadingPad)
        .padding(.trailing, Metrics.trailingPad)
    }

    /// The Global Instant as a fraction of home's civil day — where the
    /// meridian cursor crosses every lane.
    private var meridianFraction: Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = homeZone
        let instant = engine.globalInstant
        let start = calendar.startOfDay(for: instant)
        let end = calendar.startOfDay(for: start.addingTimeInterval(36 * 3600))
        return instant.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    private var lanesArea: some View {
        VStack(spacing: 0) {
            ForEach(store.locations) { location in
                locationRow(for: location)
            }
        }
        .overlay {
            GeometryReader { geometry in
                let laneWidth = geometry.size.width - Metrics.leadingPad - Metrics.trailingPad
                    - Metrics.nameWidth - Metrics.timeWidth - 2 * Metrics.columnSpacing
                let x = Metrics.leadingPad + Metrics.nameWidth + Metrics.columnSpacing
                    + laneWidth * meridianFraction
                Rectangle()
                    .fill(theme.cursor)
                    .frame(width: 1, height: geometry.size.height)
                    .shadow(color: theme.cursor, radius: 3)
                    .opacity(0.55)
                    .position(x: x, y: geometry.size.height / 2)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var locationsList: some View {
        if store.locations.count > 6 {
            ScrollViewReader { proxy in
                ScrollView {
                    lanesArea
                }
                .frame(height: 300)
                .onAppear {
                    if let selected = state.selectedLocationID { proxy.scrollTo(selected) }
                }
                .onChange(of: state.selectedLocationID) {
                    if let selected = state.selectedLocationID { proxy.scrollTo(selected) }
                }
                .onChange(of: state.inspectedLocationID) {
                    if let inspected = state.inspectedLocationID { proxy.scrollTo(inspected) }
                }
            }
        } else {
            lanesArea
        }
    }

    private func locationRow(for location: Location) -> some View {
        let instant = engine.globalInstant
        let localTime = LocalTime(of: instant, in: location.timeZone)
        let isHome = location.id == store.home?.id
        let offset = RelativeOffset(of: location.timeZone, home: homeZone, at: instant)
        let dateLabel = TimeFormatting.relativeDayLabel(
            of: instant, in: location.timeZone,
            relativeTo: instant, in: homeZone
        )
        let (time, suffix) = splitTime(localTime)
        let isSelected = state.selectedLocationID == location.id
        let isHovered = hoveredLocationID == location.id
        let caption = offsetCaption(for: location, isHome: isHome, relativeOffset: offset, at: instant)

        return VStack(spacing: 4) {
            HStack(spacing: Metrics.columnSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.cityName)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.13)
                        .lineLimit(1)
                        .help(location.cityName)
                    Button {
                        revealBothOffsets(for: location.id)
                    } label: {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(settings.animation(.easeInOut(duration: 0.2)), value: caption)
                    }
                    .buttonStyle(.plain)
                    .help(caption)
                }
                .frame(width: Metrics.nameWidth, alignment: .leading)
                MeridianLaneView(
                    lane: MeridianModel.lane(for: location, homeZone: homeZone, at: instant),
                    altitudes: MeridianModel.sunAltitudes(for: location, homeZone: homeZone, at: instant),
                    starSeed: starSeed(for: location),
                    theme: theme,
                    showsMoonPhase: settings.showMoonPhase,
                    onScrub: { raw, velocity in scrub(raw: raw, velocity: velocity) },
                    onScrubEnded: { scrubDrag = nil }
                )
                VStack(alignment: .trailing, spacing: 2) {
                    Text(time)
                        .font(.system(size: 17, weight: .medium))
                        .monospacedDigit()
                        .tracking(-0.17)
                        .lineLimit(1)
                    secondaryTrailing(for: location, dateLabel: dateLabel, suffix: suffix)
                }
                .frame(width: Metrics.timeWidth, alignment: .trailing)
            }
            if state.inspectedLocationID == location.id {
                inspectionDetails(for: location, at: instant)
            }
        }
        .padding(.leading, Metrics.leadingPad)
        .padding(.trailing, Metrics.trailingPad)
        .padding(.vertical, 7)
        .background(isSelected ? theme.selection : isHovered ? theme.hover : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedLocationID = isSelected ? nil : location.id
            if state.inspectedLocationID != state.selectedLocationID {
                state.inspectedLocationID = nil
            }
        }
        .contextMenu {
            Button("Show on Globe") {
                globeState.inspection = GlobeInspection(location: location)
                onCommand(.openGlobe)
            }
            .disabled(location.latitude == nil || location.longitude == nil)
            Button("Show Details") {
                state.selectedLocationID = location.id
                state.inspectedLocationID = location.id
            }
            Divider()
            Button("Remove Location", role: .destructive) { onCommand(.removeLocation(location)) }
                .disabled(store.locations.count <= 1)
        }
        .onHover { hovering in
            if hovering {
                hoveredLocationID = location.id
            } else if hoveredLocationID == location.id {
                hoveredLocationID = nil
            }
        }
    }

    /// Date label (accent) when the city's civil date differs from home's,
    /// otherwise the AM/PM suffix — plus the weather when enabled.
    @ViewBuilder
    private func secondaryTrailing(for location: Location, dateLabel: String?, suffix: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if let dateLabel {
                    Text(dateLabel)
                        .foregroundStyle(theme.accent)
                        .fontWeight(.semibold)
                }
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            if settings.showWeather, location.latitude != nil, location.longitude != nil {
                Group {
                    if let weather = weatherStore.weather(for: location) {
                        Label(weather.temperatureText(usesMetric: settings.usesMetricUnits), systemImage: weather.symbolName)
                            .help("Current weather, independent of the timeline")
                    } else if weatherStore.isUnavailable(for: location) {
                        Label("—", systemImage: "cloud.slash")
                            .accessibilityLabel("Weather unavailable")
                            .help("Weather unavailable. Check your connection and reopen the panel to retry.")
                    } else {
                        Text("…")
                            .accessibilityLabel("Loading weather")
                    }
                }
                .foregroundStyle(theme.secondaryText)
            }
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .animation(settings.animation(.easeInOut(duration: 0.15)), value: dateLabel)
    }

    /// A stable per-city star-field seed (String.hashValue is randomized per
    /// launch, so sum scalars instead — stars shouldn't move between opens).
    private func starSeed(for location: Location) -> Float {
        Float(location.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 997 })
    }

    /// One scrub path for every lane: the drag moves the meridian over HOME's
    /// civil day. The anchor freezes at drag start so fractions past the edge
    /// extrapolate stably; modifiers are read per event so they work mid-drag.
    private func scrub(raw: Double, velocity: CGFloat) {
        guard let home = store.home else { return }
        let modifiers = NSEvent.modifierFlags
        let drag = scrubDrag ?? (anchor: engine.globalInstant, previousRaw: raw, effective: raw)
        let effective = ScrubberLogic.effectiveDayFraction(
            raw: raw,
            previousRaw: drag.previousRaw,
            previousEffective: drag.effective,
            isPrecise: modifiers.contains(.shift)
        )
        scrubDrag = (drag.anchor, raw, effective)
        // Option disables snapping; Shift does too (precision means exact
        // minutes); fast drags skip it so snapping stays imperceptible.
        let snapping = modifiers.isDisjoint(with: [.option, .shift]) && velocity < 250
        engine.scrub(
            toDayFraction: effective,
            of: home,
            anchoredAt: drag.anchor,
            snapping: snapping
        )
    }

    /// Secondary info revealed by Return on the selected Location.
    private func inspectionDetails(for location: Location, at instant: Date) -> some View {
        let sunLabel: String = switch DayLineModel.sunDay(for: location, at: instant) {
        case let .risesAndSets(_, sunrise, sunset, _):
            "Sunrise \(TimeFormatting.timeString(LocalTime(of: sunrise, in: location.timeZone), clockFormat: clockFormat))"
                + " · Sunset \(TimeFormatting.timeString(LocalTime(of: sunset, in: location.timeZone), clockFormat: clockFormat))"
        case .twilightOnly:
            "Twilight only — the sun stays below the horizon"
        case .polarDay:
            "Polar day — the sun never sets"
        case .polarNight:
            "Polar night — the sun never rises"
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(sunLabel)
            HStack {
                Text(location.timeZone.identifier)
                Spacer()
                if let latitude = location.latitude, let longitude = location.longitude {
                    Text(String(format: "%.2f°, %.2f°", latitude, longitude))
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Relative Mode or UTC Mode caption; a click transiently shows both, and
    /// hovering swaps in the Greeting for the simulated Local Time. Home
    /// always keeps its marker — it is the axis.
    private func offsetCaption(for location: Location, isHome: Bool, relativeOffset: RelativeOffset, at instant: Date) -> String {
        let relativeText = isHome ? "Home" : TimeFormatting.relativeOffset(seconds: relativeOffset.seconds)
        let utcText = TimeFormatting.utcOffset(seconds: location.timeZone.secondsFromGMT(for: instant))
        if revealedOffsetID == location.id {
            return "\(relativeText) · \(utcText)"
        }
        if hoveredLocationID == location.id,
           settings.showGreetings,
           let country = location.country,
           let greeting = greetingProvider?.greeting(
               countryCode: country,
               at: LocalTime(of: instant, in: location.timeZone)
           ) {
            return greeting.text == greeting.gloss ? greeting.text : "\(greeting.text) · \(greeting.gloss)"
        }
        if isHome {
            return "Home · \(utcText)"
        }
        return settings.offsetMode == .relative ? relativeText : utcText
    }

    private func revealBothOffsets(for id: Location.ID) {
        withAnimation(settings.animation(.easeInOut(duration: 0.15))) { revealedOffsetID = id }
        revealResetTask?.cancel()
        revealResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, revealedOffsetID == id else { return }
            withAnimation(settings.animation(.easeInOut(duration: 0.15))) { revealedOffsetID = nil }
        }
    }

    private var addLocationFooter: some View {
        HStack {
            Button {
                state.isSearching = true
            } label: {
                HStack(spacing: 8) {
                    Text("+")
                        .font(.system(size: 14))
                        .frame(width: 18, height: 18)
                        .background(theme.pill, in: Circle())
                    Text("Add Location")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            keyChip("A")
            Button { onCommand(.openSettings) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.separator).frame(height: 1)
        }
        .padding(.top, 6)
    }

    private func keyChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.separator, lineWidth: 1))
    }

    // MARK: ⌘K command overlay

    private var commandResults: [PanelCommand] {
        CommandMatcher.commands(
            matching: state.commandQuery,
            locations: store.locations,
            offsetMode: settings.offsetMode,
            timeState: engine.state,
            cityDatabase: databaseLoader.database,
            at: engine.globalInstant
        )
    }

    /// Index of the highlighted command; ↑/↓ move it, Return executes it.
    @State private var commandSelection = 0

    private var commandOverlay: some View {
        let results = commandResults
        let highlighted = min(commandSelection, max(results.count - 1, 0))
        return overlayShell(
            placeholder: "Type a command…",
            query: $state.commandQuery,
            onSubmit: {
                if results.indices.contains(highlighted) { onCommand(results[highlighted]) }
            },
            onMoveUp: { commandSelection = max(highlighted - 1, 0) },
            onMoveDown: { commandSelection = min(highlighted + 1, max(results.count - 1, 0)) },
            emptyText: "No matching commands",
            isEmpty: results.isEmpty
        ) {
            ForEach(Array(results.enumerated()), id: \.element) { index, command in
                Button { onCommand(command) } label: {
                    HStack {
                        Text(command.title)
                            .font(.body)
                            .background(HiddenListScrollers())
                        Spacer()
                        if let shortcut = command.shortcutLabel {
                            Text(shortcut)
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.tertiaryText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(theme.pill, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    index == highlighted
                        ? RoundedRectangle(cornerRadius: 6).fill(theme.selection)
                        : nil
                )
            }
        }
        .onChange(of: state.commandQuery) { commandSelection = 0 }
    }

    /// The scaffold both overlays share: focused field, divider, list, empty state.
    private func overlayShell<Rows: View>(
        placeholder: String,
        query: Binding<String>,
        onSubmit: @escaping () -> Void,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        emptyText: String,
        isEmpty: Bool,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                FocusedTextField(
                    placeholder: placeholder,
                    text: query,
                    onSubmit: onSubmit,
                    onCancel: { state.dismissOverlays() },
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown
                )
                Button { state.dismissOverlays() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(theme.pill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
                .help("Close search (Esc)")
            }
            .padding(14)
            Rectangle().fill(theme.separator).frame(height: 1)
            List {
                rows()
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .overlay {
                if isEmpty {
                    Text(emptyText)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.secondaryText)
                        .padding(20)
                }
            }
            HStack {
                Text("↑ ↓ to choose · ↵ to select")
                Spacer()
                Text("esc to close")
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.secondaryText)
            .padding(12)
        }
    }

    // MARK: City search overlay

    private var searchResults: [City] {
        guard let database = databaseLoader.database else { return [] }
        return database.search(state.searchQuery, at: engine.globalInstant, limit: 8)
    }

    @State private var searchSelection = 0

    private var searchOverlay: some View {
        let results = searchResults
        let selected = min(searchSelection, max(results.count - 1, 0))
        let emptyText = databaseLoader.database == nil ? "Loading cities…"
            : state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Find a place to add\nSearch by city, country, or UTC offset."
                : "No cities found\nTry another city name, country, or UTC offset."
        return ScrollViewReader { proxy in
            overlayShell(
                placeholder: "City, country, or UTC offset",
                query: $state.searchQuery,
                onSubmit: {
                    if results.indices.contains(selected) { onCommand(.addLocation(results[selected])) }
                },
                onMoveUp: { searchSelection = PanelKeyLogic.movedResultSelection(from: selected, by: -1, count: results.count) },
                onMoveDown: { searchSelection = PanelKeyLogic.movedResultSelection(from: selected, by: 1, count: results.count) },
                emptyText: emptyText,
                isEmpty: results.isEmpty
            ) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, city in
                    Button { onCommand(.addLocation(city)) } label: {
                        cityRow(for: city).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(city.id)
                    .listRowBackground(index == selected ? RoundedRectangle(cornerRadius: 6).fill(theme.selection) : nil)
                    .accessibilityAddTraits(index == selected ? [.isSelected] : [])
                }
            }
            .onChange(of: searchSelection) {
                if results.indices.contains(searchSelection) { proxy.scrollTo(results[searchSelection].id) }
            }
        }
        .onChange(of: state.searchQuery) { searchSelection = 0 }
    }

    private func cityRow(for city: City) -> some View {
        let zone = TimeZone(identifier: city.timeZone)
        let time = zone.map { LocalTime(of: engine.globalInstant, in: $0) }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.body)
                    .background(HiddenListScrollers())
                Text(countryName(for: city.country) ?? city.country)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let time {
                    Text(TimeFormatting.timeString(time, clockFormat: clockFormat))
                        .font(.body.monospacedDigit())
                }
                Text(store.locations.contains(where: { $0.id == city.timeZone }) ? "Already saved" : city.timeZone)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.vertical, 2)
    }

    private func countryName(for code: String) -> String? {
        Locale.current.localizedString(forRegionCode: code)
    }
}
