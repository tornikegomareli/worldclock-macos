import Foundation
import Observation
import SwiftUI

/// How Location offsets are interpreted: relative to Home (the default) or
/// as UTC offsets.
enum OffsetMode: String, Codable {
    case relative
    case utc
}

/// The 12/24h preference: follow the system, or override.
enum ClockFormatPreference: String, Codable {
    case system
    case twelveHour
    case twentyFourHour
}

enum FirstDayOfWeek: String, Codable {
    case system
    case monday
    case sunday
}

/// Every preference, as one Codable value — the settings half of the
/// export/import configuration file.
struct SettingsSnapshot: Codable, Equatable {
    var offsetMode: OffsetMode
    var clockFormatPreference: ClockFormatPreference
    var showWeather: Bool
    var showGreetings: Bool
    var showMoonPhase: Bool
    var animationsEnabled: Bool
    var firstDayOfWeek: FirstDayOfWeek
    var autoUpdateHome: Bool
    var menuBarLocationID: String?
}

/// User preferences, persisted in UserDefaults (PRD platform decision).
@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let offsetMode = "offsetMode"
        static let clockFormat = "clockFormatPreference"
        static let showWeather = "showWeather"
        static let showGreetings = "showGreetings"
        static let showMoonPhase = "showMoonPhase"
        static let animationsEnabled = "animationsEnabled"
        static let firstDayOfWeek = "firstDayOfWeek"
        static let autoUpdateHome = "autoUpdateHome"
        static let menuBarLocationID = "menuBarLocationID"
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

    var showGreetings: Bool {
        didSet { defaults.set(showGreetings, forKey: Keys.showGreetings) }
    }

    var showMoonPhase: Bool {
        didSet { defaults.set(showMoonPhase, forKey: Keys.showMoonPhase) }
    }

    var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: Keys.animationsEnabled) }
    }

    var firstDayOfWeek: FirstDayOfWeek {
        didSet { defaults.set(firstDayOfWeek.rawValue, forKey: Keys.firstDayOfWeek) }
    }

    var autoUpdateHome: Bool {
        didSet { defaults.set(autoUpdateHome, forKey: Keys.autoUpdateHome) }
    }

    /// The Location whose time shows in the menu bar; nil keeps icon-only.
    var menuBarLocationID: String? {
        didSet { defaults.set(menuBarLocationID, forKey: Keys.menuBarLocationID) }
    }

    /// `withAnimation`-compatible: nil when the user disabled animations.
    func animation(_ animation: Animation) -> Animation? {
        animationsEnabled ? animation : nil
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            offsetMode: offsetMode,
            clockFormatPreference: clockFormatPreference,
            showWeather: showWeather,
            showGreetings: showGreetings,
            showMoonPhase: showMoonPhase,
            animationsEnabled: animationsEnabled,
            firstDayOfWeek: firstDayOfWeek,
            autoUpdateHome: autoUpdateHome,
            menuBarLocationID: menuBarLocationID
        )
    }

    func restore(_ snapshot: SettingsSnapshot) {
        offsetMode = snapshot.offsetMode
        clockFormatPreference = snapshot.clockFormatPreference
        showWeather = snapshot.showWeather
        showGreetings = snapshot.showGreetings
        showMoonPhase = snapshot.showMoonPhase
        animationsEnabled = snapshot.animationsEnabled
        firstDayOfWeek = snapshot.firstDayOfWeek
        autoUpdateHome = snapshot.autoUpdateHome
        menuBarLocationID = snapshot.menuBarLocationID
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
        showGreetings = defaults.object(forKey: Keys.showGreetings) as? Bool ?? true
        showMoonPhase = defaults.object(forKey: Keys.showMoonPhase) as? Bool ?? true
        animationsEnabled = defaults.object(forKey: Keys.animationsEnabled) as? Bool ?? true
        firstDayOfWeek = defaults.string(forKey: Keys.firstDayOfWeek)
            .flatMap(FirstDayOfWeek.init(rawValue:)) ?? .system
        autoUpdateHome = defaults.object(forKey: Keys.autoUpdateHome) as? Bool ?? false
        menuBarLocationID = defaults.string(forKey: Keys.menuBarLocationID)
    }
}
