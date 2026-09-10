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

    @Test("All preferences survive relaunch")
    @MainActor
    func allPreferencesPersist() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.offsetMode = .utc
        settings.clockFormatPreference = .twentyFourHour
        settings.showWeather = false
        settings.showGreetings = false
        settings.showMoonPhase = false
        settings.animationsEnabled = false
        settings.autoUpdateHome = true
        settings.menuBarLocationID = "Asia/Tokyo"

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.offsetMode == .utc)
        #expect(restored.clockFormatPreference == .twentyFourHour)
        #expect(!restored.showWeather)
        #expect(!restored.showGreetings)
        #expect(!restored.showMoonPhase)
        #expect(!restored.animationsEnabled)
        #expect(restored.autoUpdateHome)
        #expect(restored.menuBarLocationID == "Asia/Tokyo")
    }

    @Test("Motion policy: full normally, crossfade under Reduce Motion, none when disabled")
    @MainActor
    func motionPolicy() {
        let full = SettingsStore(defaults: makeDefaults(), reduceMotion: { false })
        #expect(full.animation(.spring(duration: 0.4)) == .spring(duration: 0.4))

        // Reduce Motion replaces every spatial animation with a crossfade.
        let reduced = SettingsStore(defaults: makeDefaults(), reduceMotion: { true })
        #expect(reduced.animation(.spring(duration: 0.4)) == .easeInOut(duration: 0.2))

        // The user's animations-off toggle beats both: instant.
        let off = SettingsStore(defaults: makeDefaults(), reduceMotion: { true })
        off.animationsEnabled = false
        #expect(off.animation(.spring(duration: 0.4)) == nil)
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
