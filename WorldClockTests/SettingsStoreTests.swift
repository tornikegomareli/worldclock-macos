import Foundation
import Testing
@testable import WorldClock

/// Preferences persist through an injected UserDefaults suite — never the
/// machine's real defaults.
@Suite("SettingsStore")
struct SettingsStoreTests {
    func makeDefaults() -> UserDefaults {
        let name = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Fresh settings: Relative Mode and the system clock format")
    @MainActor
    func freshDefaults() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(settings.offsetMode == .relative)
        #expect(settings.clockFormatPreference == .system)
    }

    @Test("Offset mode and clock format survive relaunch")
    @MainActor
    func preferencesPersist() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults)
        settings.offsetMode = .utc
        settings.clockFormatPreference = .twelveHour

        let relaunched = SettingsStore(defaults: defaults)
        #expect(relaunched.offsetMode == .utc)
        #expect(relaunched.clockFormatPreference == .twelveHour)
    }

    @Test("The clock format preference resolves overrides, pinned locale otherwise")
    @MainActor
    func clockFormatResolution() {
        // Pinned en_US: a 12-hour locale, so "system" resolves to 12-hour.
        let settings = SettingsStore(defaults: makeDefaults(), locale: Locale(identifier: "en_US"))

        settings.clockFormatPreference = .twentyFourHour
        #expect(settings.resolvedClockFormat == .twentyFourHour)

        settings.clockFormatPreference = .twelveHour
        #expect(settings.resolvedClockFormat == .twelveHour)

        settings.clockFormatPreference = .system
        #expect(settings.resolvedClockFormat == .twelveHour)
    }
}
