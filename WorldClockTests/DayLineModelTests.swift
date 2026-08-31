import Foundation
import Testing
@testable import WorldClock

/// Expected boundaries come from USNO times (fetched 2026-08-31) converted to
/// day fractions by hand: Tbilisi 2026-08-31 — civil dawn 05:57 (357 min),
/// sunrise 06:25 (385), sunset 19:36 (1176), civil dusk 20:05 (1205); each
/// divided by 1440. Tolerance 0.003 of a day (~4 minutes).
@Suite("DayLineModel")
struct DayLineModelTests {
    let tbilisi = Location(
        cityName: "Tbilisi",
        timeZone: TimeZone(identifier: "Asia/Tbilisi")!,
        latitude: 41.6938,
        longitude: 44.8015
    )
    let longyearbyen = Location(
        cityName: "Longyearbyen",
        timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!,
        latitude: 78.2232,
        longitude: 15.6267
    )

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func expectClose(_ value: Double?, _ expected: Double, tolerance: Double = 0.003) {
        guard let value else {
            Issue.record("expected \(expected), got nil")
            return
        }
        #expect(abs(value - expected) <= tolerance, "\(value) vs \(expected)")
    }

    @Test("An ordinary day has night, twilight, day, twilight, night segments at USNO boundaries")
    func ordinaryDaySegments() {
        let dayLine = DayLineModel.dayLine(for: tbilisi, at: instant("2026-08-31T11:00:00+04:00"))

        #expect(dayLine.segments.map(\.kind) == [.night, .twilight, .day, .twilight, .night])
        #expect(dayLine.segments.first?.start == 0)
        #expect(dayLine.segments.last?.end == 1)

        expectClose(dayLine.segments[0].end, 357.0 / 1440)   // civil dawn 05:57
        expectClose(dayLine.segments[1].end, 385.0 / 1440)   // sunrise 06:25
        expectClose(dayLine.segments[2].end, 1176.0 / 1440)  // sunset 19:36
        expectClose(dayLine.segments[3].end, 1205.0 / 1440)  // civil dusk 20:05
    }

    @Test("The indicator sits at the Local Time: a sun by day, a phase-correct moon by night")
    func indicatorFollowsLocalTime() {
        // 15:00 local = 900/1440 of the day; the sun is up (06:25–19:36).
        let afternoon = DayLineModel.dayLine(for: tbilisi, at: instant("2026-08-31T15:00:00+04:00"))
        expectClose(afternoon.indicatorPosition, 900.0 / 1440, tolerance: 0.0005)
        #expect(afternoon.indicator == .sun)

        // 23:00 local = 1380/1440; night. USNO: full moon 2026-08-28 → four
        // days later the phase is just past full (~0.5–0.65).
        let night = DayLineModel.dayLine(for: tbilisi, at: instant("2026-08-31T23:00:00+04:00"))
        expectClose(night.indicatorPosition, 1380.0 / 1440, tolerance: 0.0005)
        guard case let .moon(phase) = night.indicator else {
            Issue.record("expected a moon at night, got \(night.indicator)")
            return
        }
        #expect(phase > 0.5 && phase < 0.65)
    }

    @Test("Polar day is one bright segment with a sun; polar night one dark segment with a moon")
    func polarCases() {
        let midsummer = DayLineModel.dayLine(for: longyearbyen, at: instant("2026-06-21T12:00:00+02:00"))
        #expect(midsummer.segments == [DayLine.Segment(kind: .day, start: 0, end: 1)])
        #expect(midsummer.indicator == .sun)

        let midwinter = DayLineModel.dayLine(for: longyearbyen, at: instant("2026-12-21T12:00:00+01:00"))
        #expect(midwinter.segments == [DayLine.Segment(kind: .night, start: 0, end: 1)])
        guard case .moon = midwinter.indicator else {
            Issue.record("expected a moon in polar night, got \(midwinter.indicator)")
            return
        }
    }

    @Test("A Location without coordinates still renders a plausible Day Line")
    func missingCoordinatesDegrade() {
        let timeZoneOnly = Location(cityName: "Somewhere", timeZone: TimeZone(identifier: "Asia/Tbilisi")!)
        let dayLine = DayLineModel.dayLine(for: timeZoneOnly, at: instant("2026-08-31T15:00:00+04:00"))

        // Equatorial approximation: a day exists and surrounds local midday.
        #expect(dayLine.segments.map(\.kind) == [.night, .twilight, .day, .twilight, .night])
        let day = dayLine.segments[2]
        #expect(day.start < 0.5 && day.end > 0.5)
        #expect(dayLine.indicator == .sun)
    }
}
