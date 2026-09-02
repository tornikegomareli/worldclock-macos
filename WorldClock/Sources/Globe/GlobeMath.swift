import Foundation
import simd

/// The Globe's coordinate frame, pinned by the ADR-0002 spike: Greenwich at
/// +X, north at +Y, east longitudes toward +Z (RealityKit's generateSphere
/// texture mapping). The terminator renders correctly exactly when the sun
/// direction and surface positions agree in this frame.
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
            Float(cos(lat) * sin(lon))
        )
    }

    /// Jump: the orbit-camera spherical angles that put a coordinate at the
    /// center of the visible disc (camera direction == surface direction).
    static func cameraAngles(latitude: Double, longitude: Double) -> (yaw: Double, pitch: Double) {
        (yaw: .pi / 2 - longitude * .pi / 180, pitch: latitude * .pi / 180)
    }

    /// The inverse: a (unit-ish) surface position back to latitude/longitude.
    static func coordinate(fromUnitPosition position: SIMD3<Float>) -> (latitude: Double, longitude: Double) {
        let unit = simd_normalize(position)
        let latitude = asin(Double(unit.y)) * 180 / .pi
        let longitude = atan2(Double(unit.z), Double(unit.x)) * 180 / .pi
        return (latitude, longitude)
    }
}
