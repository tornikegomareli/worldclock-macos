import CoreLocation
import Foundation
import WeatherKit

/// The live WeatherProvider (ADR-0003). Requires the maintainer's WeatherKit
/// entitlement; without it every call throws and the caller renders nothing.
struct WeatherKitProvider: WeatherProvider {
    func weather(latitude: Double, longitude: Double) async throws -> Weather {
        let current = try await WeatherService.shared.weather(
            for: CLLocation(latitude: latitude, longitude: longitude),
            including: .current
        )
        return Weather(
            condition: Self.condition(from: current.condition),
            temperatureCelsius: current.temperature.converted(to: .celsius).value
        )
    }

    private static func condition(from condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch condition {
        case .clear, .mostlyClear, .hot, .sunFlurries, .sunShowers:
            .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy, .breezy, .windy:
            .cloudy
        case .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .freezingDrizzle, .freezingRain:
            .rain
        case .snow, .heavySnow, .flurries, .sleet, .blizzard, .blowingSnow, .wintryMix, .frigid, .hail:
            .snow
        case .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            .storm
        case .foggy, .haze, .smoky, .blowingDust:
            .fog
        @unknown default:
            .cloudy
        }
    }
}
