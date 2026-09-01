import CoreLocation
import Foundation
import Testing
@testable import WorldClock

/// The traveling-Home authorization policy, pure and pinned. macOS reports
/// .authorized/.authorizedAlways when the when-in-use prompt is granted.
@Suite("HomeLocationPolicy")
struct HomeLocationPolicyTests {
    @Test("Every authorization status maps to exactly the right reaction")
    func authorizationReactions() {
        #expect(HomeLocationPolicy.reaction(to: .notDetermined) == .requestPermission)
        #expect(HomeLocationPolicy.reaction(to: .authorized) == .startMonitoring)
        #expect(HomeLocationPolicy.reaction(to: .authorizedAlways) == .startMonitoring)
        #expect(HomeLocationPolicy.reaction(to: .denied) == .disableToggle)
        #expect(HomeLocationPolicy.reaction(to: .restricted) == .disableToggle)
    }
}
