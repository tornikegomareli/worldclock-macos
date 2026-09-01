import Foundation
import Observation

/// How Location offsets are interpreted: relative to Home (the default) or
/// as UTC offsets.
enum OffsetMode: String {
    case relative
    case utc
}

/// The 12/24h preference: follow the system, or override.
enum ClockFormatPreference: String {
    case system
    case twelveHour
    case twentyFourHour
}

/// User preferences, persisted in UserDefaults (PRD platform decision).
@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let offsetMode = "offsetMode"
        static let clockFormat = "clockFormatPreference"
        static let showWeather = "showWeather"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale

    var offsetMode: OffsetMode {
        didSet { defaults.set(offsetMode.rawValue, forKey: Keys.offsetMode) }
    }

    var clockFormatPreference: ClockFormatPreference {
        didSet { defaults.set(clockFormatPreference.rawValue, forKey: Keys.clockFormat) }
    }

    var showWeather: Bool {
        didSet { defaults.set(showWeather, forKey: Keys.showWeather) }
    }

    /// Whether temperatures render in Celsius, from the injected locale.
    var usesMetricUnits: Bool {
        locale.measurementSystem == .metric
    }

    var resolvedClockFormat: ClockFormat {
        switch clockFormatPreference {
        case .system: ClockFormat.system(for: locale)
        case .twelveHour: .twelveHour
        case .twentyFourHour: .twentyFourHour
        }
    }

    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        self.locale = locale
        offsetMode = defaults.string(forKey: Keys.offsetMode)
            .flatMap(OffsetMode.init(rawValue:)) ?? .relative
        clockFormatPreference = defaults.string(forKey: Keys.clockFormat)
            .flatMap(ClockFormatPreference.init(rawValue:)) ?? .system
        showWeather = defaults.object(forKey: Keys.showWeather) as? Bool ?? true
    }
}
