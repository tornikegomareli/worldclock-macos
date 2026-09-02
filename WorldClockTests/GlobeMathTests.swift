import Foundation
import Testing
@testable import WorldClock

/// The Globe's coordinate frame (ADR-0002 spike finding): Greenwich at +X,
/// north at +Y, east longitudes toward +Z. The terminator is correct exactly
/// when the sun direction matches Astronomy's subsolar point in this frame.
@Suite("GlobeMath")
struct GlobeMathTests {
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
