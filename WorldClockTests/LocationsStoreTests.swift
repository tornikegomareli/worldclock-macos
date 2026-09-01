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

    @Test("Import replaces the whole list and persists; reset reseeds")
    @MainActor
    func replaceAllAndReset() {
        let directory = makeTempDirectory()
        let store = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")

        let imported = [
            Location(
                cityName: "Kathmandu", timeZone: TimeZone(identifier: "Asia/Kathmandu")!,
                latitude: 27.7017, longitude: 85.3206, country: "NP"
            ),
            Location(
                cityName: "Sydney", timeZone: TimeZone(identifier: "Australia/Sydney")!,
                latitude: -33.8679, longitude: 151.2073, country: "AU"
            ),
        ]
        store.replaceAll(with: imported)
        #expect(store.locations == imported)

        let relaunched = makeStore(directory: directory, systemTimeZone: "Europe/Berlin")
        #expect(relaunched.locations == imported)

        relaunched.resetToSeed()
        #expect(relaunched.locations.map(\.cityName) == ["Berlin", "London", "New York", "Tokyo"])
    }

    @Test("Export → wipe → import restores Locations and preferences exactly")
    @MainActor
    func configurationRoundTrip() throws {
        let settings = SettingsStore(defaults: {
            let name = "ConfigTests-\(UUID().uuidString)"
            return UserDefaults(suiteName: name)!
        }())
        settings.offsetMode = .utc
        settings.showWeather = false
        let store = makeStore(directory: makeTempDirectory(), systemTimeZone: "Europe/Berlin")
        store.add(
            Location(
                cityName: "Kathmandu", timeZone: TimeZone(identifier: "Asia/Kathmandu")!,
                latitude: 27.7017, longitude: 85.3206, country: "NP"
            )
        )

        let exported = try ConfigurationFile(locations: store.locations, settings: settings.snapshot).encoded()

        // Wipe: brand-new stores in fresh storage.
        let wipedStore = makeStore(directory: makeTempDirectory(), systemTimeZone: "Asia/Tokyo")
        let wipedSettings = SettingsStore(defaults: {
            let name = "ConfigTests-\(UUID().uuidString)"
            return UserDefaults(suiteName: name)!
        }())
        #expect(wipedStore.locations != store.locations)

        let imported = try ConfigurationFile(decoding: exported)
        wipedStore.replaceAll(with: imported.locations)
        wipedSettings.restore(imported.settings)

        #expect(wipedStore.locations == store.locations)
        #expect(wipedSettings.snapshot == settings.snapshot)
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
