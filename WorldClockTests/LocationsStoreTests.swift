import Dependencies
import Foundation
import Testing
@testable import WorldClock

/// Every test pins `\.timeZone` explicitly and points the store at a fresh
/// temp directory — never the machine's zone or real Application Support.
@Suite("LocationsStore")
struct LocationsStoreTests {
    func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationsStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func makeStore(directory: URL, systemTimeZone: String) -> LocationsStore {
        withDependencies {
            $0.timeZone = TimeZone(identifier: systemTimeZone)!
        } operation: {
            LocationsStore(storageDirectory: directory)
        }
    }

    @Test("First launch seeds Home from the system timezone, then the default cities")
    @MainActor
    func firstLaunchSeedsDefaults() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")

        #expect(store.locations.map(\.cityName) == ["Berlin", "London", "New York", "Tokyo"])
        #expect(store.home?.timeZone.identifier == "Europe/Berlin")
    }

    @Test("Seeding skips a default city that duplicates Home")
    @MainActor
    func seedingSkipsHomeDuplicate() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "America/New_York")

        #expect(store.locations.map(\.cityName) == ["New York", "London", "Tokyo"])
        #expect(store.home?.timeZone.identifier == "America/New_York")
    }

    @Test("The first-launch seed persists: Home does not follow later system timezone changes")
    @MainActor
    func seedIsPersisted() {
        let directory = makeTempDirectory()

        _ = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")

        let relaunched = makeStore(directory: directory, systemTimeZone: "Asia/Tokyo")
        #expect(relaunched.home?.timeZone.identifier == "Europe/Berlin")
    }

    @Test("Added Locations survive relaunch: a new store on the same directory loads them")
    @MainActor
    func addedLocationsPersistAcrossRelaunch() {
        let directory = makeTempDirectory()

        let first = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        first.add(
            Location(
                cityName: "Kathmandu",
                timeZone: TimeZone(identifier: "Asia/Kathmandu")!,
                latitude: 27.7017,
                longitude: 85.3206
            )
        )

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.locations.map(\.cityName) == ["Berlin", "London", "New York", "Tokyo", "Kathmandu"])
        #expect(relaunched.locations.last?.latitude == 27.7017)
        #expect(relaunched.locations.last?.longitude == 85.3206)
    }

    @Test("Removing a Location persists across relaunch")
    @MainActor
    func removePersists() {
        let directory = makeTempDirectory()

        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        store.remove(id: "America/New_York")
        #expect(store.locations.map(\.cityName) == ["Berlin", "London", "Tokyo"])

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.locations.map(\.cityName) == ["Berlin", "London", "Tokyo"])
    }

    @Test("Reordering persists, and Home follows the new first Location")
    @MainActor
    func reorderPersistsAndMovesHome() {
        let directory = makeTempDirectory()

        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        // Move Tokyo (index 3) to the front — SwiftUI onMove semantics.
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(store.locations.map(\.cityName) == ["Tokyo", "Berlin", "London", "New York"])
        #expect(store.home?.timeZone.identifier == "Asia/Tokyo")

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.locations.map(\.cityName) == ["Tokyo", "Berlin", "London", "New York"])
        #expect(relaunched.home?.timeZone.identifier == "Asia/Tokyo")
    }

    @Test("Backfilling fills missing coordinates and country, and persists them")
    @MainActor
    func backfillCityDetails() {
        let directory = makeTempDirectory()
        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(store.home?.latitude == nil)
        #expect(store.home?.country == nil)

        store.backfillCityDetails { location in
            location.cityName == "Berlin"
                ? (latitude: 52.5200, longitude: 13.4050, country: "DE") : nil
        }

        #expect(store.home?.latitude == 52.5200)
        #expect(store.home?.longitude == 13.4050)
        #expect(store.home?.country == "DE")
        // London's seeded values are untouched.
        #expect(store.locations[1].latitude == 51.5074)
        #expect(store.locations[1].country == "GB")

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.home?.latitude == 52.5200)
        #expect(relaunched.home?.country == "DE")
    }

    @Test("Adding a Location in a timezone already in the list is refused")
    @MainActor
    func duplicateTimeZoneAddIsRefused() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")

        // Yokohama shares Asia/Tokyo with the seeded Tokyo Location.
        store.add(Location(cityName: "Yokohama", timeZone: TimeZone(identifier: "Asia/Tokyo")!))

        #expect(store.locations.map(\.cityName) == ["Berlin", "London", "New York", "Tokyo"])
    }

    @Test("Removing Home promotes the next Location to Home")
    @MainActor
    func removingHomePromotesNextLocation() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")

        store.remove(id: "Europe/Berlin")
        #expect(store.home?.timeZone.identifier == "Europe/London")
    }

    @Test("The last remaining Location cannot be removed — Home always exists")
    @MainActor
    func lastLocationCannotBeRemoved() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")

        for location in store.locations {
            store.remove(id: location.id)
        }

        #expect(store.locations.count == 1)
        #expect(store.home != nil)
    }

    @Test("Traveling: updating Home swaps the first Location to the resolved City and persists")
    @MainActor
    func updateHomeToCity() {
        let directory = makeTempDirectory()
        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")

        let tbilisi = City(
            name: "Tbilisi", asciiName: "Tbilisi", country: "GE",
            latitude: 41.6938, longitude: 44.8015, timeZone: "Asia/Tbilisi",
            alternates: [], population: 1_049_498
        )
        store.updateHome(to: tbilisi)

        #expect(store.home?.cityName == "Tbilisi")
        #expect(store.home?.timeZone.identifier == "Asia/Tbilisi")
        #expect(store.home?.country == "GE")
        #expect(store.home?.latitude == 41.6938)
        // The rest of the list is untouched.
        #expect(store.locations.map(\.cityName) == ["Tbilisi", "London", "New York", "Tokyo"])

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.home?.cityName == "Tbilisi")
    }

    @Test("Traveling into a listed timezone drops the now-duplicate row")
    @MainActor
    func updateHomeDropsDuplicateZone() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")

        // Yokohama shares Asia/Tokyo with the listed Tokyo Location.
        let yokohama = City(
            name: "Yokohama", asciiName: "Yokohama", country: "JP",
            latitude: 35.44, longitude: 139.64, timeZone: "Asia/Tokyo",
            alternates: [], population: 3_761_630
        )
        store.updateHome(to: yokohama)

        #expect(store.home?.cityName == "Yokohama")
        #expect(store.locations.map(\.cityName) == ["Yokohama", "London", "New York"])
    }

    @Test("Updating Home to the city it already is changes nothing")
    @MainActor
    func updateHomeNoOp() {
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")
        let before = store.locations

        let berlin = City(
            name: "Berlin", asciiName: "Berlin", country: "DE",
            latitude: 52.52, longitude: 13.405, timeZone: "Europe/Berlin",
            alternates: [], population: 3_426_354
        )
        store.updateHome(to: berlin)
        store.updateHome(to: berlin)

        #expect(store.locations.count == before.count)
        #expect(store.home?.cityName == "Berlin")
    }

    @Test(
        "A corrupt file recovers to seeded defaults",
        arguments: [
            "not json at all",
            #"{"wrong": "shape"}"#,
            #"[{"cityName": "Atlantis", "timeZoneIdentifier": "Sunken/Atlantis"}]"#,
        ]
    )
    @MainActor
    func corruptFileRecoversToDefaults(corruptContent: String) throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try corruptContent.write(
            to: directory.appendingPathComponent("locations.json"),
            atomically: true,
            encoding: .utf8
        )

        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(store.locations.map(\.cityName) == ["Berlin", "London", "New York", "Tokyo"])
    }
}
