import AppKit
import SwiftUI

/// Panel content: the Location list, every Local Time rendering the same
/// Global Instant. A selected Location can be removed with Delete and the
/// list drag-reordered; the first Location is Home and anchors Relative Mode
/// offsets. "+ Add Location" (or A) opens the City search overlay.
struct PanelContentView: View {
    let engine: TimeEngine
    let store: LocationsStore
    @Bindable var state: PanelState
    let databaseLoader: CityDatabaseLoader
    let settings: SettingsStore
    let weatherStore: WeatherStore
    let greetingProvider: GreetingProvider?
    let onCommand: (PanelCommand) -> Void

    /// The drag in progress: its frozen anchor day plus the raw/effective
    /// fraction accumulator that implements Shift precision.
    @State private var scrubDrag: (anchor: Date, previousRaw: Double, effective: Double)?

    /// The Location whose offset caption transiently shows both
    /// interpretations after a click.
    @State private var revealedOffsetID: Location.ID?
    @State private var revealResetTask: Task<Void, Never>?

    /// The Location under the pointer; its secondary info shows the Greeting.
    @State private var hoveredLocationID: Location.ID?

    private var clockFormat: ClockFormat { settings.resolvedClockFormat }

    var body: some View {
        VStack(spacing: 0) {
            if state.isSearching {
                searchOverlay
            } else if state.isCommandSearching {
                commandOverlay
            } else {
                timeStateHeader
                locationList
                addLocationFooter
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Time State header

    @ViewBuilder
    private var timeStateHeader: some View {
        if case .simulated = engine.state {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text("Time Travel · \(timeTravelLabel)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Now") {
                    withAnimation(settings.animation(.spring(duration: 0.4))) { engine.returnToNow() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.12))
        } else {
            HStack {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// "Tomorrow · 16:30" — the simulated moment in Home's zone, relative to
    /// the real clock.
    private var timeTravelLabel: String {
        let homeZone = store.home?.timeZone ?? .current
        let day = TimeFormatting.relativeDayLabel(
            of: engine.globalInstant, in: homeZone,
            relativeTo: engine.now, in: homeZone
        ) ?? "Today"
        let time = TimeFormatting.timeString(
            LocalTime(of: engine.globalInstant, in: homeZone),
            clockFormat: clockFormat
        )
        return "\(day) · \(time)"
    }

    // MARK: Location list

    private var locationList: some View {
        List(selection: $state.selectedLocationID) {
            ForEach(store.locations) { location in
                locationRow(for: location)
                    .tag(location.id)
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func locationRow(for location: Location) -> some View {
        let instant = engine.globalInstant
        let localTime = LocalTime(of: instant, in: location.timeZone)
        let isHome = location.id == store.home?.id
        let homeZone = store.home?.timeZone ?? location.timeZone
        let offset = RelativeOffset(of: location.timeZone, home: homeZone, at: instant)

        let dateLabel = TimeFormatting.relativeDayLabel(
            of: instant, in: location.timeZone,
            relativeTo: instant, in: homeZone
        )

        return VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.cityName)
                        .font(.body)
                        .background(HiddenListScrollers())
                    // A Button, not a tap gesture: the List's row selection
                    // swallows plain gestures on row content.
                    let caption = offsetCaption(for: location, isHome: isHome, relativeOffset: offset, at: instant)
                    Button {
                        revealBothOffsets(for: location.id)
                    } label: {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            // Crossfade + animated width whenever the caption
                            // swaps (hover greeting, click reveal, U toggle).
                            .contentTransition(.opacity)
                            .animation(settings.animation(.easeInOut(duration: 0.2)), value: caption)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        if settings.showWeather, let weather = weatherStore.weather(for: location) {
                            HStack(spacing: 3) {
                                Image(systemName: weather.condition.symbolName)
                                Text(weather.temperatureText(usesMetric: settings.usesMetricUnits))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Text(TimeFormatting.timeString(localTime, clockFormat: clockFormat))
                            .font(.title3.monospacedDigit())
                    }
                    if let dateLabel {
                        Text(dateLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(settings.animation(.easeInOut(duration: 0.15)), value: dateLabel)
            }
            DayLineView(
                dayLine: DayLineModel.dayLine(for: location, at: instant),
                showsMoonPhase: settings.showMoonPhase,
                onScrub: { raw, velocity in
                    // The anchor day freezes at drag start so fractions past
                    // the edge extrapolate stably (see TimeEngine.scrub).
                    // Modifiers are read per event, so they work mid-drag.
                    let modifiers = NSEvent.modifierFlags
                    let drag = scrubDrag ?? (anchor: engine.globalInstant, previousRaw: raw, effective: raw)
                    let effective = ScrubberLogic.effectiveDayFraction(
                        raw: raw,
                        previousRaw: drag.previousRaw,
                        previousEffective: drag.effective,
                        isPrecise: modifiers.contains(.shift)
                    )
                    scrubDrag = (drag.anchor, raw, effective)
                    // Option disables snapping; Shift does too (precision
                    // means exact minutes, and a fixed snap band would cost
                    // five times the pointer travel to escape); fast drags
                    // skip it so snapping stays imperceptible in motion.
                    let snapping = modifiers.isDisjoint(with: [.option, .shift]) && velocity < 250
                    engine.scrub(
                        toDayFraction: effective,
                        of: location,
                        anchoredAt: drag.anchor,
                        snapping: snapping
                    )
                },
                onScrubEnded: { scrubDrag = nil }
            )
            if state.inspectedLocationID == location.id {
                inspectionDetails(for: location, at: instant)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            if hovering {
                hoveredLocationID = location.id
            } else if hoveredLocationID == location.id {
                hoveredLocationID = nil
            }
        }
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
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Relative Mode or UTC Mode caption; a click transiently shows both, and
    /// hovering swaps in the Greeting for the simulated Local Time.
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
            return "\(greeting.text) · \(greeting.gloss)"
        }
        if settings.offsetMode == .relative {
            return relativeText
        }
        // Home keeps its marker in UTC Mode — it stays the reference point.
        return isHome ? "\(relativeText) · \(utcText)" : utcText
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
        Button {
            state.isSearching = true
        } label: {
            Label("Add Location", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                HStack {
                    Text(command.title)
                        .font(.body)
                        .background(HiddenListScrollers())
                    Spacer()
                    if let shortcut = command.shortcutLabel {
                        Text(shortcut)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onCommand(command) }
                .listRowBackground(
                    index == highlighted
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25))
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
            FocusedTextField(
                placeholder: placeholder,
                text: query,
                onSubmit: onSubmit,
                onCancel: { state.dismissOverlays() },
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .padding(12)
            Divider()
            List {
                rows()
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .overlay {
                if isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: City search overlay

    private var searchResults: [City] {
        guard let database = databaseLoader.database else { return [] }
        return database.search(state.searchQuery, at: engine.globalInstant, limit: 8)
    }

    private var searchOverlay: some View {
        overlayShell(
            placeholder: "City, airport code, or UTC offset",
            query: $state.searchQuery,
            onSubmit: {
                if let first = searchResults.first { onCommand(.addLocation(first)) }
            },
            emptyText: "Loading cities…",
            isEmpty: databaseLoader.database == nil
        ) {
            ForEach(searchResults) { city in
                cityRow(for: city)
                    .contentShape(Rectangle())
                    .onTapGesture { onCommand(.addLocation(city)) }
            }
        }
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
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let time {
                    Text(TimeFormatting.timeString(time, clockFormat: clockFormat))
                        .font(.body.monospacedDigit())
                }
                Text(city.timeZone)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func countryName(for code: String) -> String? {
        Locale.current.localizedString(forRegionCode: code)
    }

}
