import Foundation

/// Offline search over the bundled City index. Cities are stored
/// most-populous first (the pipeline's order), so equal-rank matches
/// stay population-ordered without re-sorting.
final class CityDatabase: Sendable {
    private let cities: [City]
    private let searchableCities: [SearchableCity]

    private struct SearchableCity {
        let index: Int
        let normalizedName: String
        let nameWords: [String]
        let normalizedAlternates: [String]
        let normalizedCountryName: String
    }

    /// English country names (pinned locale — never the machine's), memoized
    /// per ISO code across all cities.
    private static func countryNames(for cities: [City]) -> [String: String] {
        let english = Locale(identifier: "en_US")
        return Dictionary(
            uniqueKeysWithValues: Set(cities.map(\.country)).map { code in
                (code, normalize(english.localizedString(forRegionCode: code) ?? code))
            }
        )
    }

    private let timeZonesByIdentifier: [String: TimeZone]

    init(cities: [City]) {
        self.cities = cities
        timeZonesByIdentifier = Dictionary(
            uniqueKeysWithValues: Set(cities.map(\.timeZone)).compactMap { identifier in
                TimeZone(identifier: identifier).map { (identifier, $0) }
            }
        )
        let countryNames = Self.countryNames(for: cities)
        searchableCities = cities.enumerated().map { index, city in
            let normalizedName = Self.normalize(city.name)
            let normalizedAscii = Self.normalize(city.asciiName)
            var alternates = city.alternates.map(Self.normalize)
            if normalizedAscii != normalizedName {
                alternates.insert(normalizedAscii, at: 0)
            }
            return SearchableCity(
                index: index,
                normalizedName: normalizedName,
                nameWords: normalizedName.split(separator: " ").map(String.init),
                normalizedAlternates: alternates,
                normalizedCountryName: countryNames[city.country] ?? ""
            )
        }
    }

    /// `instant` is the Global Instant used for offset queries like "UTC-5",
    /// whose answer is DST-dependent. No default: callers render the one
    /// Global Instant (ADR-0001), never an implicit machine clock.
    func search(_ query: String, at instant: Date, limit: Int = 20) -> [City] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        if let offsetSeconds = Self.parseUTCOffset(normalizedQuery) {
            return Array(
                cities.filter { city in
                    timeZonesByIdentifier[city.timeZone]?.secondsFromGMT(for: instant) == offsetSeconds
                }.prefix(limit)
            )
        }

        var scored: [(score: Int, index: Int)] = []
        for city in searchableCities {
            if let score = Self.score(city, against: normalizedQuery) {
                scored.append((score, city.index))
            }
        }
        if scored.isEmpty {
            return abbreviationMatches(normalizedQuery, limit: limit)
        }
        // Tie-break on index: equal scores stay in population order.
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .prefix(limit)
            .map { cities[$0.index] }
    }

    /// "JST" → cities in Asia/Tokyo, via Foundation's abbreviation table.
    /// Runs only when nothing matches by name, so "IST" can still find Istanbul.
    private func abbreviationMatches(_ query: String, limit: Int) -> [City] {
        guard let zone = TimeZone.abbreviationDictionary[query.uppercased()] else { return [] }
        return Array(cities.filter { $0.timeZone == zone }.prefix(limit))
    }

    /// "utc+9", "utc-5", "utc+4:30" → signed seconds from GMT.
    private static func parseUTCOffset(_ query: String) -> Int? {
        let pattern = /^utc(?<sign>[+-])(?<hours>\d{1,2})(?::(?<minutes>\d{2}))?$/
        guard let match = query.wholeMatch(of: pattern),
              let hours = Int(match.hours),
              hours <= 14
        else { return nil }
        let minutes = match.minutes.flatMap { Int($0) } ?? 0
        let magnitude = hours * 3600 + minutes * 60
        return match.sign == "-" ? -magnitude : magnitude
    }

    private static func score(_ city: SearchableCity, against query: String) -> Int? {
        if city.normalizedName == query { return 0 }
        if city.normalizedName.hasPrefix(query) { return 1 }
        if city.nameWords.dropFirst().contains(where: { $0.hasPrefix(query) }) { return 2 }
        if city.normalizedAlternates.contains(query) { return 3 }
        if city.normalizedAlternates.contains(where: { $0.hasPrefix(query) }) { return 4 }
        if !city.normalizedCountryName.isEmpty, city.normalizedCountryName.hasPrefix(query) { return 5 }
        return nil
    }

    /// The City closest to a coordinate — the traveling-Home lookup.
    /// Equirectangular approximation: exact ordering matters, not distance.
    func nearestCity(latitude: Double, longitude: Double) -> City? {
        let cosLatitude = cos(latitude * .pi / 180)
        return cities.min { lhs, rhs in
            squaredDistance(from: lhs) < squaredDistance(from: rhs)
        }

        func squaredDistance(from city: City) -> Double {
            let dLatitude = city.latitude - latitude
            var dLongitude = abs(city.longitude - longitude)
            if dLongitude > 180 { dLongitude = 360 - dLongitude }
            let dLongitudeScaled = dLongitude * cosLatitude
            return dLatitude * dLatitude + dLongitudeScaled * dLongitudeScaled
        }
    }

    /// Loads the index generated by Scripts/generate_city_database.py and
    /// bundled as cities.json — fully offline.
    static func loadBundled() throws -> CityDatabase {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let cities = try JSONDecoder().decode([City].self, from: Data(contentsOf: url))
        return CityDatabase(cities: cities)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
