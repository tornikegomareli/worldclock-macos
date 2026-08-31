import Foundation
import Testing
@testable import WorldClock

/// Reference values fetched from the USNO Astronomical Applications API
/// (aa.usno.navy.mil/api) on 2026-08-31 and pinned as literals. Acceptance:
/// sunrise/sunset within ~2 minutes, moon phase within one phase-day.
@Suite("Astronomy")
struct AstronomyTests {
    let utc = TimeZone(identifier: "UTC")!

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Local wall-clock date for a y/m/d in a zone.
    func localDate(_ year: Int, _ month: Int, _ day: Int, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func expectClose(_ date: Date?, to iso: String, toleranceMinutes: Double = 2) {
        guard let date else {
            Issue.record("expected a date near \(iso), got nil")
            return
        }
        let difference = abs(date.timeIntervalSince(instant(iso))) / 60
        #expect(difference <= toleranceMinutes, "off by \(difference) minutes from \(iso)")
    }

    @Test("London summer solstice: USNO rise 04:43, set 21:22 BST")
    func londonSolsticeSunriseSunset() throws {
        let london = TimeZone(identifier: "Europe/London")!
        let day = Astronomy.sunDay(
            latitude: 51.5074, longitude: -0.1278,
            on: localDate(2026, 6, 21, in: london), timeZone: london
        )

        guard case let .risesAndSets(_, sunrise, sunset, _) = day else {
            Issue.record("expected risesAndSets, got \(day)")
            return
        }
        expectClose(sunrise, to: "2026-06-21T04:43:00+01:00")
        expectClose(sunset, to: "2026-06-21T21:22:00+01:00")
    }

    @Test("New York winter solstice: USNO rise 07:17, set 16:32, twilight 06:46/17:03 EST")
    func newYorkWinterSolstice() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let day = Astronomy.sunDay(
            latitude: 40.7128, longitude: -74.006,
            on: localDate(2026, 12, 21, in: newYork), timeZone: newYork
        )

        guard case let .risesAndSets(civilDawn, sunrise, sunset, civilDusk) = day else {
            Issue.record("expected risesAndSets, got \(day)")
            return
        }
        expectClose(civilDawn, to: "2026-12-21T06:46:00-05:00")
        expectClose(sunrise, to: "2026-12-21T07:17:00-05:00")
        expectClose(sunset, to: "2026-12-21T16:32:00-05:00")
        expectClose(civilDusk, to: "2026-12-21T17:03:00-05:00")
    }

    @Test("Tbilisi on an ordinary date: USNO rise 06:25, set 19:36 +04")
    func tbilisiOrdinaryDay() {
        let tbilisi = TimeZone(identifier: "Asia/Tbilisi")!
        let day = Astronomy.sunDay(
            latitude: 41.6938, longitude: 44.8015,
            on: localDate(2026, 8, 31, in: tbilisi), timeZone: tbilisi
        )

        guard case let .risesAndSets(civilDawn, sunrise, sunset, civilDusk) = day else {
            Issue.record("expected risesAndSets, got \(day)")
            return
        }
        expectClose(civilDawn, to: "2026-08-31T05:57:00+04:00")
        expectClose(sunrise, to: "2026-08-31T06:25:00+04:00")
        expectClose(sunset, to: "2026-08-31T19:36:00+04:00")
        expectClose(civilDusk, to: "2026-08-31T20:05:00+04:00")
    }

    @Test("Longyearbyen: polar day at midsummer, polar night at midwinter (USNO)")
    func polarDayAndNight() {
        let longyearbyen = TimeZone(identifier: "Arctic/Longyearbyen")!

        let midsummer = Astronomy.sunDay(
            latitude: 78.2232, longitude: 15.6267,
            on: localDate(2026, 6, 21, in: longyearbyen), timeZone: longyearbyen
        )
        #expect(midsummer == .polarDay)

        let midwinter = Astronomy.sunDay(
            latitude: 78.2232, longitude: 15.6267,
            on: localDate(2026, 12, 21, in: longyearbyen), timeZone: longyearbyen
        )
        #expect(midwinter == .polarNight)
    }

    @Test("Subsolar latitude hits the tropics at solstices and zero at equinox")
    func subsolarLatitude() {
        // Solstice declination is the axial tilt, 23.44° (astronomical constant).
        let june = Astronomy.subsolarPoint(at: instant("2026-06-21T12:00:00Z"))
        #expect(abs(june.latitude - 23.44) < 0.1)

        let december = Astronomy.subsolarPoint(at: instant("2026-12-21T12:00:00Z"))
        #expect(abs(december.latitude - -23.44) < 0.1)

        // 2026 March equinox: 2026-03-20 ≈ 14:46 UTC (declination crosses 0).
        let equinox = Astronomy.subsolarPoint(at: instant("2026-03-20T14:46:00Z"))
        #expect(abs(equinox.latitude) < 0.1)
    }

    @Test("Subsolar longitude sits near Greenwich at noon UTC, near the antimeridian at midnight")
    func subsolarLongitude() {
        // At 12:00 UTC the sun is over the meridian offset only by the
        // equation of time (max ±16.5 min = ±4.2°).
        let noon = Astronomy.subsolarPoint(at: instant("2026-08-31T12:00:00Z"))
        #expect(abs(noon.longitude) < 4.5)

        let midnight = Astronomy.subsolarPoint(at: instant("2026-08-31T00:00:00Z"))
        #expect(abs(midnight.longitude) > 175.5)
    }

    @Test("Longyearbyen in February: civil twilight 09:08–15:18 with no sunrise (USNO)")
    func polarTwilightOnly() {
        let longyearbyen = TimeZone(identifier: "Arctic/Longyearbyen")!
        let day = Astronomy.sunDay(
            latitude: 78.2232, longitude: 15.6267,
            on: localDate(2026, 2, 10, in: longyearbyen), timeZone: longyearbyen
        )

        guard case let .twilightOnly(civilDawn, civilDusk) = day else {
            Issue.record("expected twilightOnly, got \(day)")
            return
        }
        expectClose(civilDawn, to: "2026-02-10T09:08:00+01:00")
        expectClose(civilDusk, to: "2026-02-10T15:18:00+01:00")
    }

    @Test("New York on the spring-forward day: USNO rise 07:19, set 18:55 EDT")
    func dstTransitionDay() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let day = Astronomy.sunDay(
            latitude: 40.7128, longitude: -74.006,
            on: localDate(2026, 3, 8, in: newYork), timeZone: newYork
        )

        guard case let .risesAndSets(_, sunrise, sunset, _) = day else {
            Issue.record("expected risesAndSets, got \(day)")
            return
        }
        expectClose(sunrise, to: "2026-03-08T07:19:00-04:00")
        expectClose(sunset, to: "2026-03-08T18:55:00-04:00")
    }

    /// Circular distance between two phase fractions (0 and 1 are the same phase).
    func phaseDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }

    @Test("Moon phase within one phase-day of USNO phase instants")
    func moonPhase() {
        let onePhaseDay = 1.0 / 29.53

        // USNO 2026: Full Moon Jan 3 10:03 UT, New Moon Jan 18 19:52 UT,
        // First Quarter Jan 26 04:47 UT, Full Moon Feb 1 22:09 UT.
        #expect(phaseDistance(Astronomy.moonPhase(at: instant("2026-01-03T10:03:00Z")), 0.5) < onePhaseDay)
        #expect(phaseDistance(Astronomy.moonPhase(at: instant("2026-01-18T19:52:00Z")), 0.0) < onePhaseDay)
        #expect(phaseDistance(Astronomy.moonPhase(at: instant("2026-01-26T04:47:00Z")), 0.25) < onePhaseDay)
        #expect(phaseDistance(Astronomy.moonPhase(at: instant("2026-02-01T22:09:00Z")), 0.5) < onePhaseDay)
    }
}
