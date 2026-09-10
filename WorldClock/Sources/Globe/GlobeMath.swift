import Foundation
import simd

/// The Globe's geographic frame: Greenwich at +X, north at +Y, east toward
/// −Z. GlobeShader derives equirectangular UVs from this same frame, so the
/// Earth texture, sun, picking, and city markers stay aligned.
enum GlobeMath {
    /// Unit vector from Earth's center toward the sun at `instant`, from
    /// Astronomy's subsolar point.
    static func sunDirection(at instant: Date) -> SIMD3<Float> {
        let subsolar = Astronomy.subsolarPoint(at: instant)
        return unitPosition(latitude: subsolar.latitude, longitude: subsolar.longitude)
    }

    /// A geographic coordinate's position on the unit sphere.
    static func unitPosition(latitude: Double, longitude: Double) -> SIMD3<Float> {
        let lat = latitude * .pi / 180
        let lon = longitude * .pi / 180
        return SIMD3(
            Float(cos(lat) * cos(lon)),
            Float(sin(lat)),
            Float(-cos(lat) * sin(lon))
        )
    }

    /// Jump: the orbit-camera spherical angles that put a coordinate at the
    /// center of the visible disc (camera direction == surface direction).
    static func cameraAngles(latitude: Double, longitude: Double) -> (yaw: Double, pitch: Double) {
        (yaw: .pi / 2 + longitude * .pi / 180, pitch: latitude * .pi / 180)
    }

    static func flightDuration(
        from start: (yaw: Double, pitch: Double, distance: Double),
        to target: (yaw: Double, pitch: Double)
    ) -> Double {
        let alignment = sin(start.pitch) * sin(target.pitch)
            + cos(start.pitch) * cos(target.pitch) * cos(target.yaw - start.yaw)
        let arc = acos(min(max(alignment, -1), 1))
        let travel = min(max(arc / .pi, abs(start.distance - 2.1) / 3), 1)
        guard travel > 0.0001 else { return 0 }
        return 0.65 + 0.85 * travel
    }

    /// Pull back, travel along the shortest longitude arc, then approach.
    /// A distance of 2.1 keeps the limb visible in the panel's square stage.
    static func flightPose(
        from start: (yaw: Double, pitch: Double, distance: Double),
        to target: (yaw: Double, pitch: Double),
        progress: Double
    ) -> (yaw: Double, pitch: Double, distance: Double) {
        var deltaYaw = (target.yaw - start.yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if deltaYaw > .pi { deltaYaw -= 2 * .pi }
        if deltaYaw < -.pi { deltaYaw += 2 * .pi }
        let deltaPitch = target.pitch - start.pitch
        let travels = hypot(deltaYaw * cos(start.pitch), deltaPitch) > 0.15
        let cruiseDistance = travels ? max(start.distance, 2.65) : start.distance
        let rotation = smootherstep(progress / 0.72)
        let departure = smootherstep(progress / 0.28)
        let approach = smootherstep((progress - 0.42) / 0.58)
        let pulledBack = start.distance + (cruiseDistance - start.distance) * departure
        return (
            start.yaw + deltaYaw * rotation,
            start.pitch + deltaPitch * rotation,
            pulledBack + (2.1 - cruiseDistance) * approach
        )
    }

    /// Zero velocity and acceleration at each end avoid abrupt phase changes.
    private static func smootherstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// The inverse: a (unit-ish) surface position back to latitude/longitude.
    static func coordinate(fromUnitPosition position: SIMD3<Float>) -> (latitude: Double, longitude: Double) {
        let unit = simd_normalize(position)
        let latitude = asin(Double(unit.y)) * 180 / .pi
        let longitude = atan2(Double(-unit.z), Double(unit.x)) * 180 / .pi
        return (latitude, longitude)
    }
}
