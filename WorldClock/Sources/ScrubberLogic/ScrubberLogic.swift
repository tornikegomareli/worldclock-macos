import Foundation

/// Converts drag positions on a Day Line into candidate Global Instants.
/// Scrubbing mutates the one shared Global Instant, never a per-Location
/// time (ADR-0001).
enum ScrubberLogic {
    /// The instant at `fraction` of the Location's civil day containing
    /// `reference`. Fractions outside [0, 1] extrapolate into adjacent days,
    /// so a drag can continue past the Day Line's edge.
    static func instant(atDayFraction fraction: Double, overDayContaining reference: Date, in timeZone: TimeZone) -> Date {
        let day = civilDay(containing: reference, in: timeZone)
        return day.start.addingTimeInterval(fraction * day.seconds)
    }

    /// The civil day span containing `reference` — via 36h so DST-transition
    /// days (23h/25h) keep their real length.
    private static func civilDay(containing reference: Date, in timeZone: TimeZone) -> (start: Date, seconds: TimeInterval) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: reference)
        let nextMidnight = calendar.startOfDay(for: midnight.addingTimeInterval(36 * 3600))
        return (midnight, nextMidnight.timeIntervalSince(midnight))
    }

    /// How close (in seconds) a candidate must be to a snap target to attract.
    /// Subtle: on a panel-width Day Line a point of drag is about five
    /// minutes, so this is under two points of magnetism per target.
    static let snapThresholdSeconds: TimeInterval = 480

    /// Snap targets for the civil day containing `candidate`: every full and
    /// half hour, plus the Location's sunrise and sunset for that date
    /// (via DayLineModel/Astronomy, so they track the scrubbed date).
    static func snapTargets(for location: Location, dayContaining candidate: Date) -> [Date] {
        let day = civilDay(containing: candidate, in: location.timeZone)

        // `through` includes the next midnight, so late evening can snap to
        // the day boundary too.
        var targets = stride(from: 0.0, through: day.seconds, by: 1800).map(day.start.addingTimeInterval)
        if case let .risesAndSets(_, sunrise, sunset, _) = DayLineModel.sunDay(for: location, at: candidate) {
            targets.append(sunrise)
            targets.append(sunset)
        }
        return targets
    }

    /// Attracts `candidate` onto the nearest target within the threshold;
    /// beyond it, the drag position wins.
    static func snapped(_ candidate: Date, to targets: [Date]) -> Date {
        guard let nearest = targets.min(by: {
            abs($0.timeIntervalSince(candidate)) < abs($1.timeIntervalSince(candidate))
        }) else { return candidate }
        return abs(nearest.timeIntervalSince(candidate)) <= snapThresholdSeconds ? nearest : candidate
    }

    /// The pointer-to-time ratio while Shift is held.
    static let precisionRatio = 0.2

    /// Accumulates a drag's effective day fraction from raw pointer
    /// fractions: 1:1 normally, one fifth while precise. Modifiers may
    /// toggle mid-drag; the accumulated position carries over.
    static func effectiveDayFraction(raw: Double, previousRaw: Double, previousEffective: Double, isPrecise: Bool) -> Double {
        previousEffective + (raw - previousRaw) * (isPrecise ? precisionRatio : 1)
    }

    /// The scrub range: ±7 days around Now.
    static let scrubRangeSeconds: TimeInterval = 7 * 86400

    static func clamped(_ candidate: Date, around now: Date) -> Date {
        min(max(candidate, now.addingTimeInterval(-scrubRangeSeconds)), now.addingTimeInterval(scrubRangeSeconds))
    }
}
