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

    @Test("All preferences persist and snapshot/restore round-trips them exactly")
    @MainActor
    func snapshotRestoreRoundTrip() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.offsetMode = .utc
        settings.clockFormatPreference = .twentyFourHour
        settings.showWeather = false
        settings.showGreetings = false
        settings.showMoonPhase = false
        settings.animationsEnabled = false
        settings.firstDayOfWeek = .monday
        settings.autoUpdateHome = true
        settings.menuBarLocationID = "Asia/Tokyo"

        let snapshot = settings.snapshot

        // Wipe: a fresh suite starts from defaults…
        let restored = SettingsStore(defaults: makeDefaults())
        #expect(restored.offsetMode == .relative)
        #expect(restored.showMoonPhase)

        // …and restoring the snapshot brings every preference back.
        restored.restore(snapshot)
        #expect(restored.offsetMode == .utc)
        #expect(restored.clockFormatPreference == .twentyFourHour)
        #expect(!restored.showWeather)
        #expect(!restored.showGreetings)
        #expect(!restored.showMoonPhase)
        #expect(!restored.animationsEnabled)
        #expect(restored.firstDayOfWeek == .monday)
        #expect(restored.autoUpdateHome)
        #expect(restored.menuBarLocationID == "Asia/Tokyo")
        #expect(restored.snapshot == snapshot)
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
