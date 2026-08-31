import SwiftUI

/// Panel content: the Location list, every Local Time rendering the same
/// Global Instant. A selected Location can be removed with Delete and the
/// list drag-reordered; the first Location is Home and anchors Relative Mode
/// offsets.
struct PanelContentView: View {
    let engine: TimeEngine
    let store: LocationsStore
    @Bindable var selection: PanelSelection

    private let clockFormat = ClockFormat.system()

    var body: some View {
        List(selection: $selection.selectedLocationID) {
            ForEach(store.locations) { location in
                row(for: location)
                    .tag(location.id)
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(for location: Location) -> some View {
        let instant = engine.globalInstant
        let localTime = LocalTime(of: instant, in: location.timeZone)
        let isHome = location.id == store.home?.id
        let homeZone = store.home?.timeZone ?? location.timeZone
        let offset = RelativeOffset(of: location.timeZone, home: homeZone, at: instant)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.cityName)
                    .font(.body)
                Text(isHome ? "Home" : TimeFormatting.relativeOffset(seconds: offset.seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeFormatting.timeString(localTime, clockFormat: clockFormat))
                .font(.title3.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}
