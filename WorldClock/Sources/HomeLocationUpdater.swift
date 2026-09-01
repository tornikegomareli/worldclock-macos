import CoreLocation
import Foundation
import Observation

/// The traveling-Home authorization policy, separated from the
/// CLLocationManager shell so it stays testable.
enum HomeLocationPolicy {
    enum Reaction: Equatable {
        case requestPermission
        case startMonitoring
        case disableToggle
    }

    static func reaction(to status: CLAuthorizationStatus) -> Reaction {
        switch status {
        case .notDetermined:
            .requestPermission
        // macOS has no .authorizedWhenInUse; granting the when-in-use prompt
        // reports .authorized / .authorizedAlways.
        case .authorized, .authorizedAlways:
            .startMonitoring
        case .denied, .restricted:
            .disableToggle
        @unknown default:
            .disableToggle
        }
    }
}

/// Traveling-Home: keeps Home on the nearest City while the settings toggle
/// is on. No toggle → no CLLocationManager → no permission prompt, ever.
/// Denied or restricted permission flips the toggle back off and the app
/// degrades to the system-timezone behavior it always had.
@MainActor
final class HomeLocationUpdater: NSObject, CLLocationManagerDelegate {
    private let settings: SettingsStore
    private let store: LocationsStore
    private let databaseLoader: CityDatabaseLoader
    private var manager: CLLocationManager?

    init(settings: SettingsStore, store: LocationsStore, databaseLoader: CityDatabaseLoader) {
        self.settings = settings
        self.store = store
        self.databaseLoader = databaseLoader
        super.init()
        syncWithToggle()
    }

    /// Follows the settings toggle. Only the read is tracked; the side
    /// effects (which may themselves write the toggle) run outside tracking.
    private func syncWithToggle() {
        let enabled = withObservationTracking {
            settings.autoUpdateHome
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncWithToggle() }
        }
        if enabled {
            startIfNeeded()
        } else {
            stop()
        }
    }

    private func startIfNeeded() {
        guard manager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.distanceFilter = 25_000
        self.manager = manager
        apply(HomeLocationPolicy.reaction(to: manager.authorizationStatus))
    }

    private func apply(_ reaction: HomeLocationPolicy.Reaction) {
        guard let manager else { return }
        switch reaction {
        case .requestPermission:
            manager.requestWhenInUseAuthorization()
        case .startMonitoring:
            startMonitoring(manager)
        case .disableToggle:
            disableAutoUpdate()
        }
    }

    private func stop() {
        manager?.stopMonitoringSignificantLocationChanges()
        manager?.stopUpdatingLocation()
        manager = nil
    }

    private func startMonitoring(_ manager: CLLocationManager) {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation()
        } else {
            manager.startUpdatingLocation()
        }
    }

    /// Permission denied: toggle visibly off, no manager, no further prompts.
    /// Home stays wherever it last resolved; ticking continues untouched.
    private func disableAutoUpdate() {
        settings.autoUpdateHome = false
        stop()
    }

    private func resolveHome(latitude: Double, longitude: Double) {
        databaseLoader.load { [weak self] database in
            guard let self, settings.autoUpdateHome else { return }
            if let city = database.nearestCity(latitude: latitude, longitude: longitude) {
                store.updateHome(to: city)
            }
        }
    }

    // MARK: CLLocationManagerDelegate
    // Callbacks arrive on the run loop the manager was created on — the main
    // actor — so assume isolation rather than enqueueing unordered hops.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // A fresh manager reports .notDetermined before the user answers;
        // applying .requestPermission again is a harmless no-op.
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            apply(HomeLocationPolicy.reaction(to: status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        MainActor.assumeIsolated {
            resolveHome(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent by design: no error surface for location, like weather.
    }
}
