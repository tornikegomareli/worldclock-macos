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

    /// The frozen anchor day for the drag in progress, if any.
    @State private var scrubAnchor: Date?

    private let clockFormat = ClockFormat.system()

    var body: some View {
        VStack(spacing: 0) {
            if state.isSearching {
                searchOverlay
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
                    withAnimation(.spring(duration: 0.4)) { engine.returnToNow() }
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
                    Text(isHome ? "Home" : TimeFormatting.relativeOffset(seconds: offset.seconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeFormatting.timeString(localTime, clockFormat: clockFormat))
                        .font(.title3.monospacedDigit())
                    if let dateLabel {
                        Text(dateLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: dateLabel)
            }
            DayLineView(
                dayLine: DayLineModel.dayLine(for: location, at: instant),
                onScrub: { fraction in
                    // The anchor day freezes at drag start so fractions past
                    // the edge extrapolate stably (see TimeEngine.scrub).
                    let anchor = scrubAnchor ?? engine.globalInstant
                    scrubAnchor = anchor
                    engine.scrub(toDayFraction: fraction, in: location.timeZone, anchoredAt: anchor)
                },
                onScrubEnded: { scrubAnchor = nil }
            )
        }
        .padding(.vertical, 4)
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

    // MARK: City search overlay

    private var searchResults: [City] {
        guard let database = databaseLoader.database else { return [] }
        return database.search(state.searchQuery, at: engine.globalInstant, limit: 8)
    }

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            FocusedTextField(
                placeholder: "City, airport code, or UTC offset",
                text: $state.searchQuery,
                onSubmit: {
                    if let first = searchResults.first { add(first) }
                },
                onCancel: { state.cancelSearch() }
            )
            .padding(12)
            Divider()
            List(searchResults) { city in
                cityRow(for: city)
                    .contentShape(Rectangle())
                    .onTapGesture { add(city) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if databaseLoader.database == nil {
                    Text("Loading cities…").foregroundStyle(.secondary)
                }
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

    private func add(_ city: City) {
        guard let zone = TimeZone(identifier: city.timeZone) else { return }
        // Swap back to the list first, then insert on the next tick so the
        // new Location visibly animates into the on-screen list.
        state.cancelSearch()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.spring(duration: 0.35)) {
                store.add(
                    Location(
                        cityName: city.name,
                        timeZone: zone,
                        latitude: city.latitude,
                        longitude: city.longitude
                    )
                )
            }
        }
    }
}
