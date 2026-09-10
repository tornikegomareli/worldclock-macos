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
    var isDaylight = true

    var symbolName: String {
        condition == .clear && !isDaylight ? "moon" : condition.symbolName
    }

    /// "23°" — rounded, in the unit system the user's region uses.
    func temperatureText(usesMetric: Bool) -> String {
        let value = usesMetric ? temperatureCelsius : temperatureCelsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }
}

/// The seam weather arrives through (ADR-0003). WeatherKit implements it for
/// the maintainer's signed builds.
protocol WeatherProvider: Sendable {
    func weather(latitude: Double, longitude: Double) async throws -> Weather
}

/// Caches current weather and exposes failed requests without interrupting clocks.
@MainActor
@Observable
final class WeatherStore {
    static let timeToLive: TimeInterval = 30 * 60
    static let retryDelay: TimeInterval = 60

    private struct Entry {
        let weather: Weather
        let fetchedAt: Date
    }

    @ObservationIgnored private let provider: any WeatherProvider
    @ObservationIgnored @Dependency(\.date) private var date
    private var entries: [Location.ID: Entry] = [:]
    private var failures: [Location.ID: Date] = [:]
    private var inFlight: Set<Location.ID> = []

    init(provider: any WeatherProvider) {
        self.provider = provider
    }

    func weather(for location: Location) -> Weather? {
        guard let entry = entries[location.id],
              date.now.timeIntervalSince(entry.fetchedAt) < Self.timeToLive
        else { return nil }
        return entry.weather
    }

    func isUnavailable(for location: Location) -> Bool {
        failures[location.id] != nil
    }

    /// Fetches weather for Locations with coordinates whose cache entry is
    /// missing or stale. Never throws; never blocks time rendering.
    func refresh(_ locations: [Location]) async {
        for location in locations {
            guard let latitude = location.latitude, let longitude = location.longitude else { continue }
            guard !inFlight.contains(location.id) else { continue }
            if let entry = entries[location.id],
               date.now.timeIntervalSince(entry.fetchedAt) < Self.timeToLive {
                continue
            }
            if let failedAt = failures[location.id],
               date.now.timeIntervalSince(failedAt) < Self.retryDelay { continue }
            inFlight.insert(location.id)
            defer { inFlight.remove(location.id) }
            do {
                let weather = try await provider.weather(latitude: latitude, longitude: longitude)
                entries[location.id] = Entry(weather: weather, fetchedAt: date.now)
                failures[location.id] = nil
            } catch is CancellationError {
                return
            } catch {
                entries[location.id] = nil
                failures[location.id] = date.now
            }
        }
    }
}
