import Foundation

/// A Location's offset from Home at a given Global Instant (Relative Mode).
/// Derived through IANA rules at the instant, so DST comes free (ADR-0001).
struct RelativeOffset: Equatable {
    let seconds: Int

    init(of zone: TimeZone, home: TimeZone, at instant: Date) {
        seconds = zone.secondsFromGMT(for: instant) - home.secondsFromGMT(for: instant)
    }
}
