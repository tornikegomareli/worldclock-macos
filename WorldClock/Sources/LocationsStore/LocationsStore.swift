import Dependencies
import Foundation
import Observation

/// Owns the user's Location list: seeding, ordering, Home resolution, and
/// JSON persistence. Home is the first Location (CONTEXT.md), defaulting to
/// the system timezone on first launch.
@MainActor
@Observable
final class LocationsStore {
    private(set) var locations: [Location] {
        didSet { save() }
    }

    var home: Location? { locations.first }

    /// Application Support/WorldClock — the live storage location.
    nonisolated static var liveStorageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorldClock", isDirectory: true)
    }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let systemTimeZone: TimeZone

    init(storageDirectory: URL) {
        @Dependency(\.timeZone) var systemTimeZone
        self.systemTimeZone = systemTimeZone
        fileURL = storageDirectory.appendingPathComponent("locations.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([Location].self, from: data) {
            locations = stored
        } else {
            // Missing or corrupt file: seed and persist immediately, so Home
            // stays pinned even if the system timezone changes later.
            locations = Self.seed(homeTimeZone: systemTimeZone)
            save()
        }
    }

    func add(_ location: Location) {
        // One Location per timezone while Location.id is the zone identifier.
        guard !locations.contains(where: { $0.id == location.id }) else { return }
        locations.append(location)
    }

    func remove(id: Location.ID) {
        // Home always exists: the last remaining Location cannot be removed.
        guard locations.count > 1 else { return }
        locations.removeAll { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        locations.move(fromOffsets: source, toOffset: destination)
    }

    /// Traveling-Home: the first Location becomes the resolved City. A row
    /// that would now duplicate Home's timezone is dropped; updating to the
    /// city Home already is changes nothing.
    func updateHome(to city: City) {
        guard let timeZone = TimeZone(identifier: city.timeZone) else { return }
        let newHome = Location(
            cityName: city.name,
            timeZone: timeZone,
            latitude: city.latitude,
            longitude: city.longitude,
            country: city.country
        )
        guard home != newHome else { return }
        locations = [newHome] + locations.dropFirst().filter { $0.id != newHome.id }
    }

    /// Import: replaces the whole list (and persists it).
    func replaceAll(with imported: [Location]) {
        guard !imported.isEmpty else { return }
        locations = imported
    }

    /// Reset: back to the first-launch seed for the system timezone.
    func resetToSeed() {
        locations = Self.seed(homeTimeZone: systemTimeZone)
    }

    /// Fills in coordinates and country for Locations that lack them (e.g.
    /// Home seeded from just a timezone), using a resolver such as a City
    /// database lookup.
    func backfillCityDetails(_ resolve: (Location) -> (latitude: Double, longitude: Double, country: String)?) {
        let filled = locations.map { location -> Location in
            guard location.latitude == nil || location.longitude == nil || location.country == nil,
                  let details = resolve(location)
            else { return location }
            return Location(
                cityName: location.cityName,
                timeZone: location.timeZone,
                latitude: location.latitude ?? details.latitude,
                longitude: location.longitude ?? details.longitude,
                country: location.country ?? details.country
            )
        }
        if filled != locations {
            locations = filled
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(locations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save Locations: \(error)")
        }
    }

    private static func seed(homeTimeZone: TimeZone) -> [Location] {
        let home = Location(
            cityName: cityName(fromIdentifier: homeTimeZone.identifier),
            timeZone: homeTimeZone
        )
        let others: [Location] = [
            Location(
                cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!,
                latitude: 51.5074, longitude: -0.1278, country: "GB"
            ),
            Location(
                cityName: "New York", timeZone: TimeZone(identifier: "America/New_York")!,
                latitude: 40.7128, longitude: -74.006, country: "US"
            ),
            Location(
                cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!,
                latitude: 35.6895, longitude: 139.6917, country: "JP"
            ),
        ]
        return [home] + others.filter { $0.id != home.id }
    }

    /// "America/New_York" → "New York": the identifier's last component with
    /// underscores as spaces. A placeholder until the City database lands.
    private static func cityName(fromIdentifier identifier: String) -> String {
        let lastComponent = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return lastComponent.replacingOccurrences(of: "_", with: " ")
    }
}
