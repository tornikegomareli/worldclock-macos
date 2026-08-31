import SwiftUI

/// Panel content: one row per Location, all rendering the same Global Instant.
struct PanelContentView: View {
    let engine: TimeEngine

    private let locations = Location.defaults
    private let home = TimeZone.current
    private let clockFormat = ClockFormat.system()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(locations) { location in
                row(for: location)
                if location.id != locations.last?.id {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(for location: Location) -> some View {
        let instant = engine.globalInstant
        let localTime = LocalTime(of: instant, in: location.timeZone)
        let offset = RelativeOffset(of: location.timeZone, home: home, at: instant)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.cityName)
                    .font(.body)
                Text(TimeFormatting.relativeOffset(seconds: offset.seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeFormatting.timeString(localTime, clockFormat: clockFormat))
                .font(.title3.monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}