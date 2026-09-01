import Foundation

/// A locale-specific salutation matching a Location's simulated Local Time,
/// with its English gloss.
struct Greeting: Equatable {
    let text: String
    let gloss: String
}

/// Selects Greetings from bundled per-locale rule data (greetings.json):
/// each language divides the day at its own boundaries — rules, not
/// translations. Unknown locales yield no greeting.
final class GreetingProvider: Sendable {
    private struct RulesFile: Decodable {
        let countries: [String: String]
        let rules: [String: [Rule]]
    }

    private struct Rule: Decodable {
        let from: String
        let greeting: String
        let gloss: String
    }

    private struct Period {
        let fromMinutes: Int
        let greeting: Greeting
    }

    private let countries: [String: String]
    /// Periods per language, sorted by start minute.
    private let periods: [String: [Period]]

    init(rulesData: Data) throws {
        let file = try JSONDecoder().decode(RulesFile.self, from: rulesData)
        countries = file.countries
        periods = file.rules.mapValues { rules in
            rules.compactMap { rule -> Period? in
                let parts = rule.from.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return Period(
                    fromMinutes: parts[0] * 60 + parts[1],
                    greeting: Greeting(text: rule.greeting, gloss: rule.gloss)
                )
            }
            .sorted { $0.fromMinutes < $1.fromMinutes }
        }
    }

    static func loadBundled() throws -> GreetingProvider {
        guard let url = Bundle.main.url(forResource: "greetings", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try GreetingProvider(rulesData: Data(contentsOf: url))
    }

    /// The Greeting for a country's locale at a Local Time; nil when the
    /// locale isn't in the curated set. Before the first period of the day,
    /// the last period wraps across midnight.
    func greeting(countryCode: String, at localTime: LocalTime) -> Greeting? {
        guard let language = countries[countryCode], let periods = periods[language],
              let last = periods.last
        else { return nil }
        let minutes = localTime.hour * 60 + localTime.minute
        return periods.last { $0.fromMinutes <= minutes }?.greeting ?? last.greeting
    }
}
