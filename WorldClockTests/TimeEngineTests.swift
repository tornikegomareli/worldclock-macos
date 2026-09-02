import Clocks
import ConcurrencyExtras
import Dependencies
import Foundation
import Testing
@testable import WorldClock

/// All fixtures pin explicit IANA timezone identifiers and fixed instants — never
/// the machine's locale or clock. DST reference: in 2026, US DST starts March 8
/// and EU summer time starts March 29, so March 15 falls in the gap where New York
/// is already on EDT while London is still on GMT.
@Suite("TimeEngine")
struct TimeEngineTests {
    let tbilisi = TimeZone(identifier: "Asia/Tbilisi")!
    let london = TimeZone(identifier: "Europe/London")!
    let newYork = TimeZone(identifier: "America/New_York")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("One Global Instant renders the correct Local Time in every zone")
    func localTimesDeriveFromOneInstant() {
        let globalInstant = instant("2026-03-15T12:00:00Z")

        #expect(LocalTime(of: globalInstant, in: tbilisi) == LocalTime(hour: 16, minute: 0))
        #expect(LocalTime(of: globalInstant, in: london) == LocalTime(hour: 12, minute: 0))
        #expect(LocalTime(of: globalInstant, in: newYork) == LocalTime(hour: 8, minute: 0))
        #expect(LocalTime(of: globalInstant, in: tokyo) == LocalTime(hour: 21, minute: 0))
    }

    @Test("Relative offset from Home follows DST across fixture dates")
    func offsetsFollowDSTTransitions() {
        let winter = instant("2026-01-15T12:00:00Z")
        let dstGap = instant("2026-03-15T12:00:00Z")
        let summer = instant("2026-07-15T12:00:00Z")

        // New York from Home Tbilisi (fixed +4): EST is -5 (9h behind), EDT is -4 (8h behind).
        #expect(RelativeOffset(of: newYork, home: tbilisi, at: winter).seconds == -9 * 3600)
        #expect(RelativeOffset(of: newYork, home: tbilisi, at: dstGap).seconds == -8 * 3600)
        #expect(RelativeOffset(of: newYork, home: tbilisi, at: summer).seconds == -8 * 3600)

        // London from Home Tbilisi: GMT until March 29 2026, BST after.
        #expect(RelativeOffset(of: london, home: tbilisi, at: dstGap).seconds == -4 * 3600)
        #expect(RelativeOffset(of: london, home: tbilisi, at: summer).seconds == -3 * 3600)

        // Home relative to itself is always zero.
        #expect(RelativeOffset(of: tbilisi, home: tbilisi, at: summer).seconds == 0)
    }

    /// A TimeEngine whose wall clock reads from `date` and whose tick timing
    /// runs on `tickClock` — fully deterministic.
    @MainActor
    func makeEngine(date: LockIsolated<Date>, tickClock: TestClock<Duration> = TestClock()) -> TimeEngine {
        withDependencies {
            $0.date = DateGenerator { date.value }
            $0.continuousClock = tickClock
        } operation: {
            TimeEngine()
        }
    }

    @Test("In Now mode the Global Instant tracks the clock on each tick")
    @MainActor
    func nowModeTicks() {
        let t0 = instant("2026-01-15T12:00:00Z")
        let t1 = instant("2026-01-15T12:01:00Z")
        let date = LockIsolated(t0)
        let engine = makeEngine(date: date)

        #expect(engine.globalInstant == t0)
        date.setValue(t1)
        engine.tick()
        #expect(engine.globalInstant == t1)
    }

    @Test("Ticking fires on the minute boundary, then every minute")
    @MainActor
    func ticksAlignToMinuteBoundaries() async {
        let tickClock = TestClock()
        let date = LockIsolated(instant("2026-01-15T12:00:30Z"))
        let engine = makeEngine(date: date, tickClock: tickClock)

        engine.startTicking()
        // Let the tick task reach its first sleep before advancing — on slow
        // CI runners the TestClock can otherwise advance past an unscheduled
        // sleeper.
        for _ in 0..<20 { await Task.yield() }

        // 30 seconds to the 12:01 boundary.
        date.setValue(instant("2026-01-15T12:01:00Z"))
        await tickClock.advance(by: .seconds(30))
        #expect(engine.globalInstant == instant("2026-01-15T12:01:00Z"))

        // Then a fixed one-minute cadence.
        date.setValue(instant("2026-01-15T12:02:00Z"))
        await tickClock.advance(by: .seconds(60))
        #expect(engine.globalInstant == instant("2026-01-15T12:02:00Z"))

        engine.stopTicking()
    }

    @Test("Simulated state pins the Global Instant; ticks stop moving it")
    @MainActor
    func simulatedStateStopsTicking() async {
        let tickClock = TestClock()
        let simulated = instant("2026-07-15T18:30:00Z")
        let date = LockIsolated(instant("2026-01-15T12:00:00Z"))
        let engine = makeEngine(date: date, tickClock: tickClock)

        engine.startTicking()
        engine.simulate(simulated)
        #expect(engine.state == .simulated(simulated))
        #expect(engine.globalInstant == simulated)

        date.setValue(instant("2026-01-15T12:05:00Z"))
        await tickClock.advance(by: .seconds(120))
        #expect(engine.globalInstant == simulated)

        engine.stopTicking()
    }

    @Test("Returning to Now resumes tracking the clock")
    @MainActor
    func returnToNowResumesTicking() {
        let t0 = instant("2026-01-15T12:00:00Z")
        let date = LockIsolated(t0)
        let engine = makeEngine(date: date)

        engine.simulate(instant("2026-07-15T18:30:00Z"))
        let t1 = instant("2026-01-15T12:05:00Z")
        date.setValue(t1)
        engine.returnToNow()

        #expect(engine.state == .now)
        #expect(engine.globalInstant == t1)
    }

    @Test("Ticks align to the next minute boundary; an exact boundary stays put")
    func minuteBoundaryAlignment() {
        #expect(
            TimeEngine.nextMinuteBoundary(after: instant("2026-01-15T12:00:30Z"))
                == instant("2026-01-15T12:01:00Z")
        )
        #expect(
            TimeEngine.nextMinuteBoundary(after: instant("2026-01-15T12:00:59Z"))
                == instant("2026-01-15T12:01:00Z")
        )
        #expect(
            TimeEngine.nextMinuteBoundary(after: instant("2026-01-15T12:01:00Z"))
                == instant("2026-01-15T12:01:00Z")
        )
    }
}
