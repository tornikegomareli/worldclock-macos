import Foundation

/// Converts drag positions on a Day Line into candidate Global Instants.
/// Scrubbing mutates the one shared Global Instant, never a per-Location
/// time (ADR-0001).
enum ScrubberLogic {
    /// The instant at `fraction` of the Location's civil day containing
    /// `reference`. Fractions outside [0, 1] extrapolate into adjacent days,
    /// so a drag can continue past the Day Line's edge.
    static func instant(atDayFraction fraction: Double, overDayContaining reference: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: reference)
        let nextMidnight = calendar.startOfDay(for: midnight.addingTimeInterval(36 * 3600))
        let daySeconds = nextMidnight.timeIntervalSince(midnight)
        return midnight.addingTimeInterval(fraction * daySeconds)
    }

    /// The scrub range: ±7 days around Now.
    static let scrubRangeSeconds: TimeInterval = 7 * 86400

    static func clamped(_ candidate: Date, around now: Date) -> Date {
        min(max(candidate, now.addingTimeInterval(-scrubRangeSeconds)), now.addingTimeInterval(scrubRangeSeconds))
    }
}
