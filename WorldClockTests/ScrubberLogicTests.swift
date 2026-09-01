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

    let newYorkLocation = Location(
        cityName: "New York",
        timeZone: TimeZone(identifier: "America/New_York")!,
        latitude: 40.7128,
        longitude: -74.006
    )
    let tbilisiLocation = Location(
        cityName: "Tbilisi",
        timeZone: TimeZone(identifier: "Asia/Tbilisi")!,
        latitude: 41.6938,
        longitude: 44.8015
    )

    @Test("Snap targets are the day's full and half hours plus sunrise and sunset")
    func snapTargetsForADay() {
        let candidate = instant("2026-08-31T11:20:00+04:00")
        let targets = ScrubberLogic.snapTargets(for: tbilisiLocation, dayContaining: candidate)

        #expect(targets.contains(instant("2026-08-31T00:00:00+04:00")))
        #expect(targets.contains(instant("2026-08-31T11:30:00+04:00")))
        #expect(targets.contains(instant("2026-08-31T23:30:00+04:00")))

        // Sunrise/sunset track the scrubbed date: USNO for 2026-08-31 says
        // rise 06:25, set 19:36 (+04). The Astronomy-derived targets must sit
        // within two minutes of those.
        let sunrise = instant("2026-08-31T06:25:00+04:00")
        let sunset = instant("2026-08-31T19:36:00+04:00")
        #expect(targets.contains { abs($0.timeIntervalSince(sunrise)) < 120 })
        #expect(targets.contains { abs($0.timeIntervalSince(sunset)) < 120 })

        // The next midnight is a target too, so 23:5x can snap to the boundary.
        #expect(targets.contains(instant("2026-09-01T00:00:00+04:00")))
    }

    @Test("Sunrise snap targets move with the scrubbed date")
    func sunriseTargetsTrackTheDate() {
        // USNO New York: rise 07:17 EST on 2026-12-21, rise 07:19 EDT on
        // 2026-03-08 — different dates, different sunrise targets.
        let winterTargets = ScrubberLogic.snapTargets(
            for: newYorkLocation, dayContaining: instant("2026-12-21T12:00:00-05:00")
        )
        let winterSunrise = instant("2026-12-21T07:17:00-05:00")
        #expect(winterTargets.contains { abs($0.timeIntervalSince(winterSunrise)) < 120 })

        let springTargets = ScrubberLogic.snapTargets(
            for: newYorkLocation, dayContaining: instant("2026-03-08T12:00:00-04:00")
        )
        let springSunrise = instant("2026-03-08T07:19:00-04:00")
        #expect(springTargets.contains { abs($0.timeIntervalSince(springSunrise)) < 120 })
    }

    @Test("Snapping attracts within the threshold and lets go beyond it")
    func snappingThreshold() {
        let targets = [instant("2026-08-31T11:00:00+04:00")]

        // Six minutes off the hour (about a point of drag) snaps onto it.
        let near = instant("2026-08-31T10:54:00+04:00")
        #expect(ScrubberLogic.snapped(near, to: targets) == instant("2026-08-31T11:00:00+04:00"))

        // Twelve minutes off stays where the drag put it — snapping attracts,
        // it never yanks across half the gap to the next half-hour target.
        let far = instant("2026-08-31T11:12:00+04:00")
        #expect(ScrubberLogic.snapped(far, to: targets) == far)

        // The same holds against the full target set of a real day.
        let realTargets = ScrubberLogic.snapTargets(for: tbilisiLocation, dayContaining: far)
        #expect(ScrubberLogic.snapped(far, to: realTargets) == far)
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

        engine.scrub(toDayFraction: 15.0 / 24, of: newYorkLocation, anchoredAt: engine.globalInstant)

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

        engine.scrub(toDayFraction: 1.25, of: tbilisiLocation, anchoredAt: anchor)
        let first = engine.globalInstant
        engine.scrub(toDayFraction: 1.25, of: tbilisiLocation, anchoredAt: anchor)
        engine.scrub(toDayFraction: 1.25, of: tbilisiLocation, anchoredAt: anchor)

        #expect(engine.globalInstant == first)
        #expect(first == instant("2026-01-16T06:00:00+04:00"))
    }

    @Test("Scrubbing clamps to ±7 days around the injected Now")
    @MainActor
    func engineScrubClamps() {
        let reference = instant("2026-01-15T12:00:00+04:00")
        let engine = makeEngine(now: reference)

        engine.scrub(toDayFraction: 30, of: tbilisiLocation, anchoredAt: engine.globalInstant)

        #expect(engine.globalInstant == instant("2026-01-22T12:00:00+04:00"))
    }

    @Test("Scrubbing snaps near a full hour; Option bypasses snapping entirely")
    @MainActor
    func scrubSnapsAndOptionBypasses() {
        let reference = instant("2026-01-15T12:00:00+04:00")
        // 10:57 is 657 minutes into the day — three minutes shy of 11:00.
        let fraction = 657.0 / 1440

        let snappingEngine = makeEngine(now: reference)
        snappingEngine.scrub(toDayFraction: fraction, of: tbilisiLocation, anchoredAt: reference)
        #expect(snappingEngine.globalInstant == instant("2026-01-15T11:00:00+04:00"))

        let bypassEngine = makeEngine(now: reference)
        bypassEngine.scrub(toDayFraction: fraction, of: tbilisiLocation, anchoredAt: reference, snapping: false)
        #expect(bypassEngine.globalInstant == instant("2026-01-15T10:57:00+04:00"))
    }

    @Test("Shift precision: pointer movement maps to a fifth of the time movement, toggling mid-drag")
    func shiftPrecisionRatio() {
        // Normal movement passes through 1:1.
        let normal = ScrubberLogic.effectiveDayFraction(
            raw: 0.5, previousRaw: 0.4, previousEffective: 0.4, isPrecise: false
        )
        #expect(abs(normal - 0.5) < 0.000001)

        // Precise movement advances at one fifth of the pointer.
        let precise = ScrubberLogic.effectiveDayFraction(
            raw: 0.6, previousRaw: 0.5, previousEffective: 0.5, isPrecise: true
        )
        #expect(abs(precise - 0.52) < 0.000001)

        // Releasing Shift mid-drag resumes 1:1 from the accumulated position.
        let resumed = ScrubberLogic.effectiveDayFraction(
            raw: 0.7, previousRaw: 0.6, previousEffective: precise, isPrecise: false
        )
        #expect(abs(resumed - 0.62) < 0.000001)
    }
}
