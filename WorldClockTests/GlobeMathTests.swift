import Foundation
import Testing
@testable import WorldClock

/// The Globe's coordinate frame (ADR-0002 spike finding): Greenwich at +X,
/// north at +Y, east longitudes toward −Z. The terminator is correct exactly
/// when the sun direction matches Astronomy's subsolar point in this frame.
@Suite("GlobeMath")
struct GlobeMathTests {
    @Test("Nearby flights are quicker than cross-world flights; centered cities arrive immediately")
    func flightTimingMatchesTravel() {
        let start = (yaw: 0.0, pitch: 0.0, distance: 2.1)
        let nearby = GlobeMath.flightDuration(from: start, to: (0.1, 0))
        let distant = GlobeMath.flightDuration(from: start, to: (.pi, 0))
        #expect(nearby < distant)
        #expect(nearby >= 0.6 && distant <= 1.5)
        #expect(GlobeMath.flightDuration(from: start, to: (0, 0)) == 0)
        #expect(GlobeMath.flightDuration(from: (0, 0, 4), to: (0, 0)) > 0)
    }

    @Test("Flight timing uses the short date-line crossing")
    func flightTimingAcrossDateLine() {
        let across = GlobeMath.flightDuration(from: (170 * .pi / 180, 0, 2.1), to: (-170 * .pi / 180, 0))
        let nearby = GlobeMath.flightDuration(from: (0, 0, 2.1), to: (20 * .pi / 180, 0))
        #expect(abs(across - nearby) < 0.0001)
    }

    @Test("The camera settles with near-zero acceleration")
    func softLanding() {
        let start = (yaw: 0.0, pitch: 0.0, distance: 2.1)
        let target = (yaw: 2.0, pitch: 0.5)
        let h = 0.0001
        let a = GlobeMath.flightPose(from: start, to: target, progress: 1 - 2 * h).distance
        let b = GlobeMath.flightPose(from: start, to: target, progress: 1 - h).distance
        let c = GlobeMath.flightPose(from: start, to: target, progress: 1).distance
        #expect(abs((c - 2 * b + a) / (h * h)) < 0.1)
    }

    @Test("Flight starts at the current pose and ends closer, facing the city")
    func flightEndpoints() {
        let start = (yaw: 1.0, pitch: 0.3, distance: 2.6)
        let target = GlobeMath.cameraAngles(latitude: 41.69, longitude: 44.8)
        let first = GlobeMath.flightPose(from: start, to: target, progress: 0)
        let last = GlobeMath.flightPose(from: start, to: target, progress: 1)
        #expect(first.yaw == start.yaw && first.pitch == start.pitch && first.distance == start.distance)
        #expect(abs(last.yaw - target.yaw) < 0.0001)
        #expect(abs(last.pitch - target.pitch) < 0.0001)
        #expect(abs(last.distance - 2.1) < 0.0001)
    }

    @Test("City-to-city flight pulls back before approaching")
    func flightPullback() {
        let start = (yaw: 1.0, pitch: 0.3, distance: 2.1)
        let target = (yaw: 3.0, pitch: 0.5)
        let departure = GlobeMath.flightPose(from: start, to: target, progress: 0.3)
        let approach = GlobeMath.flightPose(from: start, to: target, progress: 0.85)
        #expect(abs(departure.distance - 2.65) < 0.0001)
        #expect(approach.distance < departure.distance)
        #expect(abs(approach.yaw - target.yaw) < 0.0001)
    }

    @Test("Flight crosses the date line by the short arc")
    func flightCrossesDateLine() {
        let start = GlobeMath.cameraAngles(latitude: 0, longitude: 170)
        let target = GlobeMath.cameraAngles(latitude: 0, longitude: -170)
        let end = GlobeMath.flightPose(from: (start.yaw, start.pitch, 2.1), to: target, progress: 1)
        #expect(abs(end.yaw - start.yaw - 20 * .pi / 180) < 0.0001)
    }

    @Test("Selecting the centered city does not pull back")
    func centeredFlight() {
        let start = (yaw: 1.0, pitch: 0.3, distance: 2.1)
        for step in 0...100 {
            let pose = GlobeMath.flightPose(from: start, to: (1.0, 0.3), progress: Double(step) / 100)
            #expect(pose.distance == 2.1)
            #expect(pose.yaw == 1.0 && pose.pitch == 0.3)
        }
    }

    @Test("Geographic axes keep east on the right when looking north-up at Greenwich")
    func geographicAxes() {
        expectClose(GlobeMath.unitPosition(latitude: 0, longitude: 0), SIMD3(1, 0, 0))
        expectClose(GlobeMath.unitPosition(latitude: 90, longitude: 0), SIMD3(0, 1, 0))
        expectClose(GlobeMath.unitPosition(latitude: 0, longitude: 90), SIMD3(0, 0, -1))
        expectClose(GlobeMath.unitPosition(latitude: 0, longitude: -90), SIMD3(0, 0, 1))
    }

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func expectClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.02) {
        #expect(abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance,
                "\(a) vs \(b)")
    }

    @Test("The sun direction tracks the subsolar point for fixture dates")
    func sunDirectionFixtures() {
        // Equinox, ~solar noon at Greenwich: sun over (≈0°, ≈0°) → +X.
        // (12:07 UTC ≈ apparent noon: the equation of time is about −7 min
        // in late March.)
        let equinoxNoon = GlobeMath.sunDirection(at: instant("2026-03-20T12:07:00Z"))
        expectClose(equinoxNoon, SIMD3(1, 0, 0))

        // Twelve hours later the sun is over the antimeridian → −X.
        let equinoxMidnight = GlobeMath.sunDirection(at: instant("2026-03-21T00:07:00Z"))
        expectClose(equinoxMidnight, SIMD3(-1, 0, 0), tolerance: 0.03)

        // June solstice noon: lifted north by the axial tilt.
        let solsticeNoon = GlobeMath.sunDirection(at: instant("2026-06-21T12:02:00Z"))
        #expect(abs(solsticeNoon.y - sin(23.44 * Float.pi / 180)) < 0.01)
        #expect(solsticeNoon.x > 0.9)
    }

    @Test("Terminator check: the subsolar point's surface position is exactly sunlit")
    func subsolarPointIsSunlit() {
        for iso in ["2026-01-15T03:30:00Z", "2026-06-21T18:45:00Z", "2026-09-02T12:00:00Z"] {
            let date = instant(iso)
            let subsolar = Astronomy.subsolarPoint(at: date)
            let surface = GlobeMath.unitPosition(latitude: subsolar.latitude, longitude: subsolar.longitude)
            let sun = GlobeMath.sunDirection(at: date)
            // dot(normal, sun) == 1 at the subsolar point: local noon, the
            // brightest point of the terminator model.
            let alignment = surface.x * sun.x + surface.y * sun.y + surface.z * sun.z
            #expect(alignment > 0.9999, "misaligned at \(iso): \(alignment)")
        }
    }

    @Test("Jump: camera angles put the target city at the disc center")
    func cameraAnglesFaceTheTarget() {
        let fixtures: [(Double, Double)] = [
            (41.69, 44.80),    // Tbilisi
            (-33.87, 151.21),  // Sydney
            (40.71, -74.01),   // New York
            (64.15, -21.94),   // Reykjavík
        ]
        for (latitude, longitude) in fixtures {
            let angles = GlobeMath.cameraAngles(latitude: latitude, longitude: longitude)
            // A camera on spherical coordinates (yaw, pitch) sits along this
            // direction; the target faces it when the directions coincide.
            let cameraDirection = SIMD3(
                Float(cos(angles.pitch) * sin(angles.yaw)),
                Float(sin(angles.pitch)),
                Float(cos(angles.pitch) * cos(angles.yaw))
            )
            let target = GlobeMath.unitPosition(latitude: latitude, longitude: longitude)
            let alignment = cameraDirection.x * target.x + cameraDirection.y * target.y + cameraDirection.z * target.z
            #expect(alignment > 0.9999, "camera misses (\(latitude), \(longitude)): \(alignment)")
        }
    }

    @Test("Unit position and coordinate are inverses — the picking round trip")
    func coordinateRoundTrip() {
        let fixtures: [(Double, Double)] = [
            (41.69, 44.80),    // Tbilisi
            (-33.87, 151.21),  // Sydney
            (40.71, -74.01),   // New York
            (0, 0),            // Gulf of Guinea
            (-77.85, 166.67),  // McMurdo
        ]
        for (latitude, longitude) in fixtures {
            let position = GlobeMath.unitPosition(latitude: latitude, longitude: longitude)
            let coordinate = GlobeMath.coordinate(fromUnitPosition: position)
            #expect(abs(coordinate.latitude - latitude) < 0.01, "lat \(latitude)")
            #expect(abs(coordinate.longitude - longitude) < 0.01, "lon \(longitude)")
        }
    }
}
