import Foundation
import Testing
@testable import WorldClock

/// Fixture cities are pinned literals in population order (the pipeline's
/// output order), so ranking assertions come from the spec, not the code.
@Suite("CityDatabase")
struct CityDatabaseTests {
    let tokyo = City(
        name: "Tokyo", asciiName: "Tokyo", country: "JP",
        latitude: 35.69, longitude: 139.69, timeZone: "Asia/Tokyo",
        alternates: ["Edo"], population: 9_733_276
    )
    let london = City(
        name: "London", asciiName: "London", country: "GB",
        latitude: 51.51, longitude: -0.13, timeZone: "Europe/London",
        alternates: ["LON"], population: 8_961_989
    )
    let newYork = City(
        name: "New York", asciiName: "New York", country: "US",
        latitude: 40.71, longitude: -74.01, timeZone: "America/New_York",
        alternates: ["NYC", "New Amsterdam"], population: 8_804_190
    )
    let sanFrancisco = City(
        name: "San Francisco", asciiName: "San Francisco", country: "US",
        latitude: 37.77, longitude: -122.42, timeZone: "America/Los_Angeles",
        alternates: ["SFO", "Frisco"], population: 873_965
    )
    let kabul = City(
        name: "Kabul", asciiName: "Kabul", country: "AF",
        latitude: 34.53, longitude: 69.17, timeZone: "Asia/Kabul",
        alternates: [], population: 3_043_532
    )
    let londonderry = City(
        name: "Londonderry", asciiName: "Londonderry", country: "GB",
        latitude: 55.0, longitude: -7.31, timeZone: "Europe/London",
        alternates: [], population: 83_652
    )

    var database: CityDatabase {
        CityDatabase(cities: [tokyo, london, newYork, sanFrancisco, kabul, londonderry])
    }

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// For queries whose results don't depend on the instant.
    var fixtureInstant: Date { instant("2026-01-15T12:00:00Z") }

    @Test("Name prefix matches rank the more populous city first")
    func namePrefixRanking() {
        let results = database.search("lon", at: fixtureInstant)
        #expect(results.map(\.name) == ["London", "Londonderry"])
    }

    @Test("A query matching a later word of the name still finds the city")
    func wordPrefixMatch() {
        #expect(database.search("york", at: fixtureInstant).map(\.name) == ["New York"])
        #expect(database.search("francis", at: fixtureInstant).map(\.name) == ["San Francisco"])
    }

    @Test("Matching is case- and diacritic-insensitive")
    func caseAndDiacriticInsensitive() {
        #expect(database.search("TOKYO", at: fixtureInstant).map(\.name) == ["Tokyo"])
        #expect(database.search("tōkyō", at: fixtureInstant).map(\.name) == ["Tokyo"])
    }

    @Test("Airport codes and historic alternate names find their city")
    func alternateAndAirportCode() {
        #expect(database.search("SFO", at: fixtureInstant).map(\.name) == ["San Francisco"])
        #expect(database.search("new amsterdam", at: fixtureInstant).map(\.name) == ["New York"])
    }

    @Test("A name match outranks an alternate match for the same query")
    func nameOutranksAlternate() {
        // "lon" is a prefix of London's name and of London's alternate "LON";
        // it is also a prefix of Londonderry's name. Names win, then population.
        let results = database.search("lon", at: fixtureInstant)
        #expect(results.first?.name == "London")
    }

    @Test("A country query finds its cities, most populous first")
    func countrySearch() {
        #expect(database.search("japan", at: instant("2026-01-15T12:00:00Z")).map(\.name) == ["Tokyo"])
        #expect(
            database.search("united kingdom", at: instant("2026-01-15T12:00:00Z")).map(\.name)
                == ["London", "Londonderry"]
        )
    }

    @Test("A timezone abbreviation finds the cities in that zone")
    func timeZoneAbbreviation() {
        #expect(database.search("JST", at: fixtureInstant).map(\.name) == ["Tokyo"])
        #expect(database.search("jst", at: fixtureInstant).map(\.name) == ["Tokyo"])
    }

    @Test("A UTC offset finds cities at that offset for the given Global Instant")
    func utcOffset() {
        let winter = instant("2026-01-15T12:00:00Z")
        let summer = instant("2026-07-15T12:00:00Z")

        #expect(database.search("UTC+9", at: winter).map(\.name) == ["Tokyo"])
        #expect(database.search("utc+4:30", at: winter).map(\.name) == ["Kabul"])

        // New York is UTC-5 only outside DST.
        #expect(database.search("UTC-5", at: winter).map(\.name) == ["New York"])
        #expect(database.search("UTC-5", at: summer).isEmpty)
        #expect(database.search("UTC-4", at: summer).map(\.name) == ["New York"])
    }

    @Test("Empty and garbage queries return nothing")
    func emptyAndGarbageQueries() {
        #expect(database.search("", at: fixtureInstant).isEmpty)
        #expect(database.search("   ", at: fixtureInstant).isEmpty)
        #expect(database.search("zzzzqqq", at: fixtureInstant).isEmpty)
        #expect(database.search("!@#$%^", at: fixtureInstant).isEmpty)
    }

    @Test("The nearest City resolves from a coordinate — the traveling-Home lookup")
    func nearestCity() {
        // Heathrow is London's, not Londonderry's.
        #expect(database.nearestCity(latitude: 51.47, longitude: -0.45)?.name == "London")
        // Newark airport resolves to New York.
        #expect(database.nearestCity(latitude: 40.69, longitude: -74.17)?.name == "New York")
        // Yokohama's coordinate is nearest to Tokyo in this fixture set.
        #expect(database.nearestCity(latitude: 35.44, longitude: 139.64)?.name == "Tokyo")
        // An empty database resolves nothing.
        #expect(CityDatabase(cities: []).nearestCity(latitude: 0, longitude: 0) == nil)
    }

    @Test("The bundled index loads offline and finds well-known cities")
    func bundledIndexLoads() throws {
        let bundled = try CityDatabase.loadBundled()

        let tokyo = try #require(bundled.search("Tokyo", at: fixtureInstant).first)
        #expect(tokyo.timeZone == "Asia/Tokyo")

        let sanFrancisco = try #require(bundled.search("SFO", at: fixtureInstant).first)
        #expect(sanFrancisco.name == "San Francisco")
    }
}
