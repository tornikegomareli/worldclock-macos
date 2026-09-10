import Foundation
import Observation

/// What the Globe inspector shows for a picked place — a saved Location or
/// any City. All values derive from the shared Global Instant at render time.
struct GlobeInspection: Equatable, Identifiable {
    var id: String { "\(name)|\(latitude)|\(longitude)" }
    let name: String
    let countryCode: String?
    let timeZone: TimeZone
    let latitude: Double
    let longitude: Double
    /// Present when the place isn't saved yet — powers "Add to Clocks".
    let addableCity: City?

    func savedLocation(in locations: [Location]) -> Location? {
        locations.first { $0.id == timeZone.identifier }
    }

    func isHome(_ home: Location?) -> Bool {
        guard let home else { return false }
        return name == home.cityName && timeZone.identifier == home.id
    }

    init(location: Location) {
        name = location.cityName
        countryCode = location.country
        timeZone = location.timeZone
        latitude = location.latitude ?? 0
        longitude = location.longitude ?? 0
        addableCity = nil
    }

    init?(city: City, savedLocations: [Location]) {
        guard let timeZone = TimeZone(identifier: city.timeZone) else { return nil }
        name = city.name
        countryCode = city.country
        self.timeZone = timeZone
        latitude = city.latitude
        longitude = city.longitude
        let isSaved = savedLocations.contains { $0.id == city.timeZone }
        addableCity = isSaved ? nil : city
    }
}

/// The Globe's UI state, shared between the scene, the window's key routing,
/// and the SwiftUI overlays.
@MainActor
@Observable
final class GlobeState {
    var isFlying = false
    var hasArrived = false
    var inspection: GlobeInspection?
    var isJumping = false
    var jumpQuery = ""
    var jumpSelection = 0

    func cancelJump() {
        isJumping = false
        jumpQuery = ""
        jumpSelection = 0
    }

    /// Esc inside the Globe walks back: Jump overlay → inspector → locations.
    enum EscapeStep {
        case cancelJump
        case closeInspection
        case closeGlobe
    }

    var escapeStep: EscapeStep {
        if isJumping { return .cancelJump }
        if inspection != nil { return .closeInspection }
        return .closeGlobe
    }
}
