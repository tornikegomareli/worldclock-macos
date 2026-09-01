import Foundation
import Testing
@testable import WorldClock

/// ⌘K command matching: fuzzy ranking over command titles, city-parameter
/// commands through the same CityDatabase as Add Location, and contextual
/// defaults.
@Suite("CommandMatcher")
struct CommandMatcherTests {
    let locations = [
        Location(cityName: "Tbilisi", timeZone: TimeZone(identifier: "Asia/Tbilisi")!),
        Location(cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!),
        Location(cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!),
    ]

    let kathmandu = City(
        name: "Kathmandu", asciiName: "Kathmandu", country: "NP",
        latitude: 27.70, longitude: 85.32, timeZone: "Asia/Kathmandu",
        alternates: [], population: 1_442_271
    )
    let yokohama = City(
        name: "Yokohama", asciiName: "Yokohama", country: "JP",
        latitude: 35.44, longitude: 139.64, timeZone: "Asia/Tokyo",
        alternates: [], population: 3_761_630
    )

    var database: CityDatabase { CityDatabase(cities: [kathmandu, yokohama]) }

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func commands(_ query: String, timeState: TimeState = .now, offsetMode: OffsetMode = .relative) -> [PanelCommand] {
        CommandMatcher.commands(
            matching: query,
            locations: locations,
            offsetMode: offsetMode,
            timeState: timeState,
            cityDatabase: database,
            at: instant("2026-09-01T12:00:00Z")
        )
    }

    @Test("An empty query lists contextual defaults")
    func emptyQueryDefaults() {
        let nowCommands = commands("")
        #expect(nowCommands.contains(.openSettings))
        #expect(nowCommands.contains(.openGlobe))
        #expect(nowCommands.contains(.switchToUTCMode))
        // Not in Time Travel: no Return to Now, and no switch to the mode
        // already active.
        #expect(!nowCommands.contains(.returnToNow))
        #expect(!nowCommands.contains(.switchToRelativeMode))

        let travelCommands = commands("", timeState: .simulated(instant("2026-09-01T15:00:00Z")), offsetMode: .utc)
        #expect(travelCommands.first == .returnToNow)
        #expect(travelCommands.contains(.switchToRelativeMode))
    }

    @Test("Fuzzy matching finds commands by fragments and ranks prefixes first")
    func fuzzyRanking() {
        #expect(commands("sett").first == .openSettings)
        #expect(commands("utc").first == .switchToUTCMode)
        #expect(commands("now", timeState: .simulated(instant("2026-09-01T15:00:00Z"))).contains(.returnToNow))

        // "glob" is a prefix of Globe's word — Open Globe outranks any
        // mere subsequence match.
        #expect(commands("glob").first == .openGlobe)
    }

    @Test("A no-result query returns nothing")
    func noResults() {
        #expect(commands("zzzzqq").isEmpty)
    }

    @Test("'add <city>' searches the same City database as Add Location")
    func addCityCommand() {
        #expect(commands("add kath") == [.addLocation(kathmandu)])
        // Yokohama's timezone is already in the list (Tokyo): the add
        // command is excluded, matching the store's duplicate refusal.
        #expect(commands("add yoko").isEmpty)
    }

    @Test("'show' and 'remove' target existing Locations by prefix")
    func showAndRemoveCommands() {
        #expect(commands("show lon") == [.showLocation(locations[1])])
        #expect(commands("remove tok") == [.removeLocation(locations[2])])
        #expect(commands("remove kath").isEmpty)
    }

    @Test("A bare city fragment offers Show for listed cities and Add for new ones")
    func bareCityQuery() {
        let tokyoResults = commands("toky")
        #expect(tokyoResults.contains(.showLocation(locations[2])))

        let kathmanduResults = commands("kathm")
        #expect(kathmanduResults.contains(.addLocation(kathmandu)))
    }
}
