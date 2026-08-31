import Dependencies
import Foundation
import Testing
@testable import WorldClock

/// Scrubbing converts a drag position on a Location's Day Line into a
/// Global Instant (ADR-0001) — never a per-Location time. Fixtures pin
/// explicit zones and instants.
@Suite("ScrubberLogic")
struct ScrubberLogicTests {
    let tbilisi = TimeZone(identifier: "Asia/Tbilisi")!
    let newYork = TimeZone(identifier: "America/New_York")!

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("A drag fraction maps to that fraction of the Location's civil day")
    func fractionMapsIntoTheDay() {
        // 15:00 is 15/24 of an ordinary day.
        let result = ScrubberLogic.instant(
            atDayFraction: 15.0 / 24,
            overDayContaining: instant("2026-01-15T11:00:00+04:00"),
            in: tbilisi
        )
        #expect(result == instant("2026-01-15T15:00:00+04:00"))
    }

    @Test("On a spring-forward day the fraction spans the real 23-hour day")
    func fractionOnDSTTransitionDay() {
        // New York 2026-03-08 has 23 wall-clock hours. Three quarters of the
        // day is midnight + 17h15m absolute, which the clock shows as 18:15 EDT.
        let result = ScrubberLogic.instant(
            atDayFraction: 0.75,
            overDayContaining: instant("2026-03-08T12:00:00-04:00"),
            in: newYork
        )
        #expect(result == instant("2026-03-08T18:15:00-04:00"))
    }

    @Test("Dragging past the Day Line's edge extrapolates into the adjacent day")
    func fractionExtrapolatesBeyondTheDay() {
        let reference = instant("2026-01-15T11:00:00+04:00")

        let past = ScrubberLogic.instant(atDayFraction: 1.25, overDayContaining: reference, in: tbilisi)
        #expect(past == instant("2026-01-16T06:00:00+04:00"))

        let before = ScrubberLogic.instant(atDayFraction: -0.25, overDayContaining: reference, in: tbilisi)
        #expect(before == instant("2026-01-14T18:00:00+04:00"))
    }

    @Test("Candidate instants clamp to ±7 days around Now")
    func clampsToSevenDays() {
        let now = instant("2026-01-15T12:00:00Z")

        let withinRange = instant("2026-01-20T08:00:00Z")
        #expect(ScrubberLogic.clamped(withinRange, around: now) == withinRange)

        let tooFar = instant("2026-01-30T12:00:00Z")
        #expect(ScrubberLogic.clamped(tooFar, around: now) == instant("2026-01-22T12:00:00Z"))

        let tooEarly = instant("2026-01-01T12:00:00Z")
        #expect(ScrubberLogic.clamped(tooEarly, around: now) == instant("2026-01-08T12:00:00Z"))
    }

    @MainActor
    func makeEngine(now: Date) -> TimeEngine {
        withDependencies {
            $0.date = DateGenerator { now }
        } operation: {
            TimeEngine()
        }
    }

    @Test("Scrubbing New York to 15:00 renders every other city's correct Local Time")
    @MainActor
    func scrubbingNewYorkRendersAllCities() {
        // The CONTEXT.md worked example, in summer (New York on EDT, -4):
        // 15:00 in New York is one Global Instant that renders 23:00 in
        // Tbilisi (+4), 20:00 in London (BST, +1), and 04:00 next day in
        // Tokyo (+9).
        let reference = instant("2026-07-15T12:00:00-04:00")
        let engine = makeEngine(now: reference)

        engine.scrub(toDayFraction: 15.0 / 24, in: newYork, anchoredAt: engine.globalInstant)

        let globalInstant = engine.globalInstant
        #expect(engine.state == .simulated(globalInstant))
        #expect(LocalTime(of: globalInstant, in: newYork) == LocalTime(hour: 15, minute: 0))
        #expect(LocalTime(of: globalInstant, in: TimeZone(identifier: "Asia/Tbilisi")!) == LocalTime(hour: 23, minute: 0))
        #expect(LocalTime(of: globalInstant, in: TimeZone(identifier: "Europe/London")!) == LocalTime(hour: 20, minute: 0))
        #expect(LocalTime(of: globalInstant, in: TimeZone(identifier: "Asia/Tokyo")!) == LocalTime(hour: 4, minute: 0))
    }

    @Test("A drag held past the edge stays anchored — it does not run away a day per event")
    @MainActor
    func heldDragDoesNotRunAway() {
        let reference = instant("2026-01-15T12:00:00+04:00")
        let engine = makeEngine(now: reference)
        let anchor = engine.globalInstant

        engine.scrub(toDayFraction: 1.25, in: tbilisi, anchoredAt: anchor)
        let first = engine.globalInstant
        engine.scrub(toDayFraction: 1.25, in: tbilisi, anchoredAt: anchor)
        engine.scrub(toDayFraction: 1.25, in: tbilisi, anchoredAt: anchor)

        #expect(engine.globalInstant == first)
        #expect(first == instant("2026-01-16T06:00:00+04:00"))
    }

    @Test("Scrubbing clamps to ±7 days around the injected Now")
    @MainActor
    func engineScrubClamps() {
        let reference = instant("2026-01-15T12:00:00+04:00")
        let engine = makeEngine(now: reference)

        engine.scrub(toDayFraction: 30, in: tbilisi, anchoredAt: engine.globalInstant)

        #expect(engine.globalInstant == instant("2026-01-22T12:00:00+04:00"))
    }
}
