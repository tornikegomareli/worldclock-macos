import Foundation
import Testing
@testable import WorldClock

@Suite("MeridianModel")
struct MeridianModelTests {
    // 2026-01-15 12:00:00 UTC — a plain winter day, no DST transitions.
    private let instant = Date(timeIntervalSince1970: 1_768_478_400)
    private let homeZone = TimeZone(identifier: "Europe/London")!

    private let london = Location(
        cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!,
        latitude: 51.5074, longitude: -0.1278
    )
    private let tokyo = Location(
        cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!,
        latitude: 35.6762, longitude: 139.6503
    )
    private let sanFrancisco = Location(
        cityName: "San Francisco", timeZone: TimeZone(identifier: "America/Los_Angeles")!,
        latitude: 37.7749, longitude: -122.4194
    )
    private let kathmandu = Location(
        cityName: "Kathmandu", timeZone: TimeZone(identifier: "Asia/Kathmandu")!,
        latitude: 27.7172, longitude: 85.324
    )
    private let sydney = Location(
        cityName: "Sydney", timeZone: TimeZone(identifier: "Australia/Sydney")!,
        latitude: -33.8688, longitude: 151.2093
    )

    private var homeWindow: (start: Date, seconds: TimeInterval) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = homeZone
        let start = calendar.startOfDay(for: instant)
        let end = calendar.startOfDay(for: start.addingTimeInterval(36 * 3600))
        return (start, end.timeIntervalSince(start))
    }

    @Test func homeLaneMatchesItsOwnDayLine() {
        let lane = MeridianModel.lane(for: london, homeZone: homeZone, at: instant)
        guard case let .risesAndSets(dawn, sunrise, sunset, dusk) = DayLineModel.sunDay(for: london, at: instant) else {
            Issue.record("Expected an ordinary winter day in London")
            return
        }
        let boundaries = [dawn, sunrise, sunset, dusk].map {
            $0.timeIntervalSince(homeWindow.start) / homeWindow.seconds
        }
        #expect(lane.segments.map(\.kind) == [.night, .twilight, .day, .twilight, .night])
        #expect(lane.segments.dropLast().map(\.end) == boundaries)
        #expect(lane.indicator == .sun)
    }

    @Test func lanesCoverTheFullDayContiguously() {
        for location in [london, tokyo, sanFrancisco, kathmandu, sydney] {
            let lane = MeridianModel.lane(for: location, homeZone: homeZone, at: instant)
            #expect(lane.segments.first?.start == 0)
            #expect(lane.segments.last?.end == 1)
            for (current, next) in zip(lane.segments, lane.segments.dropFirst()) {
                #expect(abs(current.end - next.start) < 1e-9)
                #expect(current.kind != next.kind)
                #expect(current.end >= current.start)
            }
        }
    }

    @Test func indicatorSitsAtTheMeridianForEveryLocation() {
        let window = homeWindow
        let expected = instant.timeIntervalSince(window.start) / window.seconds
        for location in [london, tokyo, sanFrancisco, sydney] {
            let lane = MeridianModel.lane(for: location, homeZone: homeZone, at: instant)
            #expect(abs(lane.indicatorPosition - expected) < 1e-9)
        }
    }

    /// The lane's kind at any home-day fraction must match what the location's
    /// own sun events say about that instant.
    @Test func kindAtProbeMatchesLocationSunState() {
        let window = homeWindow
        for location in [tokyo, sanFrancisco, kathmandu, sydney] {
            let lane = MeridianModel.lane(for: location, homeZone: homeZone, at: instant)
            for step in 1...23 {
                let fraction = Double(step) / 24
                let probe = window.start.addingTimeInterval(fraction * window.seconds)
                guard case let .risesAndSets(dawn, rise, set, dusk) =
                    DayLineModel.sunDay(for: location, at: probe)
                else {
                    Issue.record("Expected rise/set for \(location.cityName)")
                    continue
                }
                // Skip probes too close to a boundary to classify robustly.
                let boundaries = [dawn, rise, set, dusk]
                guard boundaries.allSatisfy({ abs($0.timeIntervalSince(probe)) > 120 }) else { continue }
                let expected: DayLine.SegmentKind =
                    (rise...set).contains(probe) ? .day
                    : (dawn...rise).contains(probe) || (set...dusk).contains(probe) ? .twilight
                    : .night
                let segment = lane.segments.first { $0.start <= fraction && fraction < $0.end }
                #expect(
                    segment?.kind == expected,
                    "\(location.cityName) at fraction \(fraction): \(String(describing: segment?.kind)) != \(expected)"
                )
            }
        }
    }

    /// The altitude curve behind the lane shader: winter London is well up at
    /// its own noon, deep below the horizon at midnight; Tokyo's peak lands in
    /// London's early morning (its noon is 3 AM home time).
    @Test func sunAltitudesFollowTheHomeAxis() {
        let londonCurve = MeridianModel.sunAltitudes(for: london, homeZone: homeZone, at: instant)
        #expect(londonCurve.count == 25)
        #expect(londonCurve[12] > 5)
        #expect(londonCurve[0] < -30)

        let tokyoCurve = MeridianModel.sunAltitudes(for: tokyo, homeZone: homeZone, at: instant)
        let peak = tokyoCurve.firstIndex(of: tokyoCurve.max() ?? 0) ?? -1
        #expect((2...5).contains(peak), "Tokyo peak at index \(peak)")
    }

    @Test func polarNightLaneIsAllNight() {
        let longyearbyen = Location(
            cityName: "Longyearbyen", timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!,
            latitude: 78.2232, longitude: 15.6267
        )
        let lane = MeridianModel.lane(for: longyearbyen, homeZone: homeZone, at: instant)
        #expect(lane.segments == [DayLine.Segment(kind: .night, start: 0, end: 1)])
    }
}
