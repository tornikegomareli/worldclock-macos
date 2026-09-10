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
    /// The Location's sun events for the civil day containing `instant`.
    /// A Location without coordinates (seeded from a timezone alone)
    /// degrades to an equatorial point at its zone's mean solar longitude.
    static func sunDay(for location: Location, at instant: Date) -> Astronomy.SunDay {
        let offsetHours = Double(location.timeZone.secondsFromGMT(for: instant)) / 3600
        return Astronomy.sunDay(
            latitude: location.latitude ?? 0,
            longitude: location.longitude ?? offsetHours * 15,
            on: instant,
            timeZone: location.timeZone
        )
    }
}
