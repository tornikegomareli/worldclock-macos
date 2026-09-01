import Foundation

/// Everything ⌘K can do. Titles are what the overlay lists; shortcut labels
/// make ⌘K the discoverability surface for the direct keys.
enum PanelCommand: Hashable {
    case addLocation(City)
    case showLocation(Location)
    case removeLocation(Location)
    case openGlobe
    case switchToUTCMode
    case switchToRelativeMode
    case returnToNow
    case openSettings

    var title: String {
        switch self {
        case let .addLocation(city): "Add \(city.name)"
        case let .showLocation(location): "Show \(location.cityName)"
        case let .removeLocation(location): "Remove \(location.cityName)"
        case .openGlobe: "Open Globe"
        case .switchToUTCMode: "Switch to UTC Mode"
        case .switchToRelativeMode: "Switch to Relative Mode"
        case .returnToNow: "Return to Now"
        case .openSettings: "Settings"
        }
    }

    var shortcutLabel: String? {
        switch self {
        // Only keys that perform this exact command; A and ⌫ act on other
        // targets (the search overlay, the selected row), so no chip.
        case .switchToUTCMode, .switchToRelativeMode: "U"
        case .returnToNow: "N"
        case .addLocation, .removeLocation, .showLocation, .openGlobe, .openSettings: nil
        }
    }
}

/// Fuzzy command matching for the ⌘K overlay.
enum CommandMatcher {
    /// Ranked commands for a query. An empty query lists contextual defaults;
    /// "add/show/remove <city>" carry a city parameter, with Add searching
    /// the same CityDatabase as Add Location.
    static func commands(
        matching query: String,
        locations: [Location],
        offsetMode: OffsetMode,
        timeState: TimeState,
        cityDatabase: CityDatabase?,
        at instant: Date,
        limit: Int = 8
    ) -> [PanelCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        var staticCommands: [PanelCommand] = []
        if timeState != .now {
            staticCommands.append(.returnToNow)
        }
        staticCommands.append(offsetMode == .relative ? .switchToUTCMode : .switchToRelativeMode)
        staticCommands.append(.openGlobe)
        staticCommands.append(.openSettings)

        guard !trimmed.isEmpty else {
            return Array(staticCommands.prefix(limit))
        }

        // Verb-prefixed city commands.
        if let cityQuery = parameter(of: "add", in: trimmed) {
            return addCommands(matching: cityQuery, locations: locations, cityDatabase: cityDatabase, at: instant, limit: limit)
        }
        if let cityQuery = parameter(of: "show", in: trimmed) {
            return matchingLocations(cityQuery, in: locations).map(PanelCommand.showLocation)
        }
        if let cityQuery = parameter(of: "remove", in: trimmed) {
            return matchingLocations(cityQuery, in: locations).map(PanelCommand.removeLocation)
        }

        // Bare queries: static commands by fuzzy score, then Show for
        // existing Locations, then Add suggestions from the database.
        var scored = staticCommands.compactMap { command in
            fuzzyScore(query: trimmed, in: command.title).map { (command: command, score: $0) }
        }
        scored.sort { ($0.score, $0.command.title.count) < ($1.score, $1.command.title.count) }
        var results = scored.map(\.command)

        results += matchingLocations(trimmed, in: locations).map(PanelCommand.showLocation)
        results += addCommands(matching: trimmed, locations: locations, cityDatabase: cityDatabase, at: instant, limit: 2)

        return Array(results.prefix(limit))
    }

    // MARK: Matching pieces

    /// "add kath" → "kath" for verb "add"; nil when the query doesn't start
    /// with the verb.
    private static func parameter(of verb: String, in query: String) -> String? {
        guard query.hasPrefix(verb + " ") else { return nil }
        return String(query.dropFirst(verb.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    private static func addCommands(
        matching cityQuery: String,
        locations: [Location],
        cityDatabase: CityDatabase?,
        at instant: Date,
        limit: Int
    ) -> [PanelCommand] {
        guard let cityDatabase, !cityQuery.isEmpty else { return [] }
        let existingZones = Set(locations.map(\.id))
        return cityDatabase.search(cityQuery, at: instant, limit: limit + existingZones.count)
            .filter { !existingZones.contains($0.timeZone) }
            .prefix(limit)
            .map(PanelCommand.addLocation)
    }

    private static func matchingLocations(_ query: String, in locations: [Location]) -> [Location] {
        guard !query.isEmpty else { return locations }
        return locations.filter { $0.cityName.lowercased().hasPrefix(query) }
    }

    /// Lower is better: 0 title prefix, 1 word prefix, 2 substring,
    /// 3 subsequence; nil when the query doesn't match at all.
    private static func fuzzyScore(query: String, in title: String) -> Int? {
        let title = title.lowercased()
        if title.hasPrefix(query) { return 0 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        if title.contains(query) { return 2 }
        var remaining = Substring(query)
        for character in title where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return 3 }
        }
        return nil
    }
}
