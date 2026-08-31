import Foundation

/// A Location's horizontal 24-hour timeline: night dark, daylight bright,
/// twilight transitions, with the time indicator at the Local Time.
struct DayLine: Equatable {
    enum SegmentKind: Equatable {
        case night
        case twilight
        case day
    }

    /// A contiguous span of the day, as fractions of the 24h civil day [0, 1].
    struct Segment: Equatable {
        let kind: SegmentKind
        let start: Double
        let end: Double
    }

    enum Indicator: Equatable {
        case sun
        case moon(phase: Double)
    }

    let segments: [Segment]
    /// The Local Time as a fraction of the day [0, 1].
    let indicatorPosition: Double
    let indicator: Indicator
}

/// Maps (Location, Global Instant, Astronomy) to a renderable Day Line.
enum DayLineModel {
    static func dayLine(for location: Location, at instant: Date) -> DayLine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let midnight = calendar.startOfDay(for: instant)
        // Via 36h so DST-transition days (23h/25h) keep correct fractions.
        let nextMidnight = calendar.startOfDay(for: midnight.addingTimeInterval(36 * 3600))
        let daySeconds = nextMidnight.timeIntervalSince(midnight)

        func fraction(of date: Date) -> Double {
            min(max(date.timeIntervalSince(midnight) / daySeconds, 0), 1)
        }

        // A Location without coordinates (seeded from a timezone alone)
        // degrades to an equatorial point at its zone's mean solar longitude.
        let offsetHours = Double(location.timeZone.secondsFromGMT(for: instant)) / 3600
        let latitude = location.latitude ?? 0
        let longitude = location.longitude ?? offsetHours * 15

        let sunDay = Astronomy.sunDay(
            latitude: latitude,
            longitude: longitude,
            on: instant,
            timeZone: location.timeZone
        )

        let segments: [DayLine.Segment]
        let isDaytime: Bool
        switch sunDay {
        case let .risesAndSets(civilDawn, sunrise, sunset, civilDusk):
            let dawn = fraction(of: civilDawn)
            let rise = fraction(of: sunrise)
            let set = fraction(of: sunset)
            let dusk = fraction(of: civilDusk)
            segments = [
                DayLine.Segment(kind: .night, start: 0, end: dawn),
                DayLine.Segment(kind: .twilight, start: dawn, end: rise),
                DayLine.Segment(kind: .day, start: rise, end: set),
                DayLine.Segment(kind: .twilight, start: set, end: dusk),
                DayLine.Segment(kind: .night, start: dusk, end: 1),
            ]
            isDaytime = (sunrise...sunset).contains(instant)
        case let .twilightOnly(civilDawn, civilDusk):
            let dawn = fraction(of: civilDawn)
            let dusk = fraction(of: civilDusk)
            segments = [
                DayLine.Segment(kind: .night, start: 0, end: dawn),
                DayLine.Segment(kind: .twilight, start: dawn, end: dusk),
                DayLine.Segment(kind: .night, start: dusk, end: 1),
            ]
            isDaytime = false
        case .polarDay:
            segments = [DayLine.Segment(kind: .day, start: 0, end: 1)]
            isDaytime = true
        case .polarNight:
            segments = [DayLine.Segment(kind: .night, start: 0, end: 1)]
            isDaytime = false
        }

        return DayLine(
            segments: segments,
            indicatorPosition: fraction(of: instant),
            indicator: isDaytime ? .sun : .moon(phase: Astronomy.moonPhase(at: instant))
        )
    }
}
