import Foundation
import Testing
@testable import WorldClock

/// Greetings are per-locale rules over the Local Time (never translations of
/// one schedule): locales divide the day differently.
@Suite("GreetingProvider")
struct GreetingProviderTests {
    let provider = try! GreetingProvider.loadBundled()

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("Rules select by locale and Local Time — Japan divides the day at 11:00")
    func ruleSelection() {
        #expect(
            provider.greeting(countryCode: "JP", at: LocalTime(hour: 8, minute: 0))
                == Greeting(text: "おはようございます", gloss: "Good morning")
        )
        #expect(
            provider.greeting(countryCode: "JP", at: LocalTime(hour: 14, minute: 0))?.text == "こんにちは"
        )
        // Arabic switches to the evening greeting at noon — not at 18:00.
        #expect(
            provider.greeting(countryCode: "EG", at: LocalTime(hour: 13, minute: 0))
                == Greeting(text: "مساء الخير", gloss: "Good evening")
        )
        // Greece stays on Καλημέρα well into the afternoon.
        #expect(
            provider.greeting(countryCode: "GR", at: LocalTime(hour: 16, minute: 0))?.text == "Καλημέρα"
        )
    }

    @Test("Before the first rule of the day, the last rule wraps across midnight")
    func midnightWrap() {
        #expect(
            provider.greeting(countryCode: "JP", at: LocalTime(hour: 2, minute: 0))?.text == "こんばんは"
        )
    }

    @Test("Unknown locales show no greeting")
    func unknownLocale() {
        #expect(provider.greeting(countryCode: "ZZ", at: LocalTime(hour: 8, minute: 0)) == nil)
        #expect(provider.greeting(countryCode: "AQ", at: LocalTime(hour: 8, minute: 0)) == nil)
    }

    @Test("The greeting follows the simulated Local Time during Time Travel")
    func timeTravelCorrectness() {
        // A Global Instant that is morning in Tokyo (08:00 JST = 23:00 UTC).
        let simulated = instant("2026-09-01T08:00:00+09:00")
        let tokyoLocalTime = LocalTime(of: simulated, in: TimeZone(identifier: "Asia/Tokyo")!)

        #expect(provider.greeting(countryCode: "JP", at: tokyoLocalTime)?.gloss == "Good morning")

        // The same instant is evening in New York (19:00 EDT the previous day).
        let newYorkLocalTime = LocalTime(of: simulated, in: TimeZone(identifier: "America/New_York")!)
        #expect(provider.greeting(countryCode: "US", at: newYorkLocalTime)?.text == "Good evening")
    }
}
