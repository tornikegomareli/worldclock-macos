import Dependencies
import Foundation
import Observation

/// Our own condition vocabulary, mapped from whatever backend implements
/// WeatherProvider (ADR-0003).
enum WeatherCondition: Equatable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case fog

    /// The small secondary glyph shown beside the time.
    var symbolName: String {
        switch self {
        case .clear: "sun.max"
        case .cloudy: "cloud"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .storm: "cloud.bolt"
        case .fog: "cloud.fog"
        }
    }
}

struct Weather: Equatable, Sendable {
    let condition: WeatherCondition
    let temperatureCelsius: Double

    /// "23°" — rounded, in the unit system the user's region uses.
    func temperatureText(usesMetric: Bool) -> String {
        let value = usesMetric ? temperatureCelsius : temperatureCelsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }
}

/// The seam weather arrives through (ADR-0003). WeatherKit implements it for
/// the maintainer's builds; contributor builds degrade to silent absence.
protocol WeatherProvider: Sendable {
    func weather(latitude: Double, longitude: Double) async throws -> Weather
}

/// Caches per-Location weather with a TTL. Every failure — no network, no
/// entitlement, API error — is silent: the Location simply has no weather.
@MainActor
@Observable
final class WeatherStore {
    static let timeToLive: TimeInterval = 30 * 60

    private struct Entry {
        let weather: Weather
        let fetchedAt: Date
    }

    @ObservationIgnored private let provider: any WeatherProvider
    @ObservationIgnored @Dependency(\.date) private var date
    private var entries: [Location.ID: Entry] = [:]

    init(provider: any WeatherProvider) {
        self.provider = provider
    }

    func weather(for location: Location) -> Weather? {
        entries[location.id]?.weather
    }

    /// Fetches weather for Locations with coordinates whose cache entry is
    /// missing or stale. Never throws; never blocks time rendering.
    func refresh(_ locations: [Location]) async {
        for location in locations {
            guard let latitude = location.latitude, let longitude = location.longitude else { continue }
            if let entry = entries[location.id],
               date.now.timeIntervalSince(entry.fetchedAt) < Self.timeToLive {
                continue
            }
            if let weather = try? await provider.weather(latitude: latitude, longitude: longitude) {
                entries[location.id] = Entry(weather: weather, fetchedAt: date.now)
            }
        }
    }
}
