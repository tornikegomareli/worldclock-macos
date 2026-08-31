import Dependencies
import Foundation
import Observation

/// The Time State: whether the Global Instant tracks the real clock (Now)
/// or the user has moved it (Time Travel).
enum TimeState: Equatable {
    case now
    case simulated(Date)
}

/// Owns the Time State and publishes the one Global Instant every surface
/// renders (ADR-0001). Ticks in Now mode; a simulated instant never moves.
///
/// The wall clock comes from `\.date` and tick timing from `\.continuousClock`,
/// so tests drive both deterministically (ADR-0004).
@MainActor
@Observable
final class TimeEngine {
    private(set) var state: TimeState = .now
    private(set) var globalInstant: Date

    /// The real clock, regardless of Time State — for "relative to now"
    /// display like the Time Travel header.
    var now: Date { date.now }

    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.continuousClock) private var tickClock
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init() {
        @Dependency(\.date.now) var now
        globalInstant = now
    }

    func tick() {
        guard state == .now else { return }
        globalInstant = date.now
    }

    func simulate(_ instant: Date) {
        state = .simulated(instant)
        globalInstant = instant
    }

    func returnToNow() {
        state = .now
        globalInstant = date.now
    }

    /// Scrubbing: converts a Day Line drag into the one Global Instant
    /// (ADR-0001), clamped to ±7 days around Now. `anchor` is the instant
    /// whose civil day the Day Line showed when the drag started — frozen for
    /// the whole drag so fractions past the edge extrapolate stably instead
    /// of re-anchoring on every event.
    func scrub(toDayFraction fraction: Double, in timeZone: TimeZone, anchoredAt anchor: Date) {
        guard fraction.isFinite else { return }
        let candidate = ScrubberLogic.instant(
            atDayFraction: fraction,
            overDayContaining: anchor,
            in: timeZone
        )
        simulate(ScrubberLogic.clamped(candidate, around: date.now))
    }

    /// The first whole-minute instant at or after `instant`.
    nonisolated static func nextMinuteBoundary(after instant: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (instant.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    /// Ticks at the next minute boundary, then every minute, so the Panel's
    /// Local Times update the moment the minute rolls over.
    func startTicking() {
        stopTicking()
        tickTask = Task {
            let boundaryDelay = Self.nextMinuteBoundary(after: date.now).timeIntervalSince(date.now)
            guard (try? await tickClock.sleep(for: .seconds(boundaryDelay))) != nil else { return }
            tick()
            while !Task.isCancelled {
                guard (try? await tickClock.sleep(for: .seconds(60))) != nil else { return }
                tick()
            }
        }
    }

    func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
