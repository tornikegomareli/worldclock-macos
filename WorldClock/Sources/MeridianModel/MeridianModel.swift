import Foundation

/// The Meridian layout: every Location's lane shares one 24-hour axis — the
/// HOME civil day containing the Global Instant — and a single meridian
/// cursor crosses all lanes at that instant. This maps a Location's sun
/// events (which are instants, zone-free) into home-day fractions.
enum MeridianModel {
    /// The location's night/twilight/day lane over the home civil day
    /// containing `instant`, with the indicator at the meridian.
    static func lane(for location: Location, homeZone: TimeZone, at instant: Date) -> DayLine {
        var homeCalendar = Calendar(identifier: .gregorian)
        homeCalendar.timeZone = homeZone
        let windowStart = homeCalendar.startOfDay(for: instant)
        // Via 36h so DST-transition days (23h/25h) keep correct fractions.
        let windowEnd = homeCalendar.startOfDay(for: windowStart.addingTimeInterval(36 * 3600))
        let windowSeconds = windowEnd.timeIntervalSince(windowStart)

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = location.timeZone

        // Walk the location's local civil days overlapping the home window,
        // collecting (kind, start, end) spans as instants.
        var spans: [(kind: DayLine.SegmentKind, start: Date, end: Date)] = []
        var dayStart = localCalendar.startOfDay(for: windowStart)
        while dayStart < windowEnd {
            let dayEnd = localCalendar.startOfDay(for: dayStart.addingTimeInterval(36 * 3600))
            let probe = dayStart.addingTimeInterval(dayEnd.timeIntervalSince(dayStart) / 2)
            let clip = { (date: Date) in min(max(date, dayStart), dayEnd) }
            switch DayLineModel.sunDay(for: location, at: probe) {
            case let .risesAndSets(dawn, rise, set, dusk):
                spans.append((.night, dayStart, clip(dawn)))
                spans.append((.twilight, clip(dawn), clip(rise)))
                spans.append((.day, clip(rise), clip(set)))
                spans.append((.twilight, clip(set), clip(dusk)))
                spans.append((.night, clip(dusk), dayEnd))
            case let .twilightOnly(dawn, dusk):
                spans.append((.night, dayStart, clip(dawn)))
                spans.append((.twilight, clip(dawn), clip(dusk)))
                spans.append((.night, clip(dusk), dayEnd))
            case .polarDay:
                spans.append((.day, dayStart, dayEnd))
            case .polarNight:
                spans.append((.night, dayStart, dayEnd))
            }
            dayStart = dayEnd
        }

        // Clip to the home window, convert to fractions, and merge neighbors
        // of the same kind (night runs across local midnights).
        var segments: [DayLine.Segment] = []
        for span in spans {
            let start = max(span.start, windowStart)
            let end = min(span.end, windowEnd)
            guard end > start else { continue }
            let segment = DayLine.Segment(
                kind: span.kind,
                start: start.timeIntervalSince(windowStart) / windowSeconds,
                end: end.timeIntervalSince(windowStart) / windowSeconds
            )
            if let last = segments.last, last.kind == segment.kind {
                segments[segments.count - 1] = DayLine.Segment(
                    kind: last.kind, start: last.start, end: segment.end
                )
            } else {
                segments.append(segment)
            }
        }
        if let first = segments.first {
            segments[0] = DayLine.Segment(kind: first.kind, start: 0, end: first.end)
        }
        if let last = segments.last {
            segments[segments.count - 1] = DayLine.Segment(kind: last.kind, start: last.start, end: 1)
        }

        let meridian = instant.timeIntervalSince(windowStart) / windowSeconds
        let isDaytime = segments.contains { $0.kind == .day && $0.start <= meridian && meridian <= $0.end }
        return DayLine(
            segments: segments,
            indicatorPosition: meridian,
            indicator: isDaytime ? .sun : .moon(phase: Astronomy.moonPhase(at: instant))
        )
    }
}
