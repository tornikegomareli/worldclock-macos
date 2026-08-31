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

    init(storageDirectory: URL) {
        @Dependency(\.timeZone) var systemTimeZone
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
            Location(cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!),
            Location(cityName: "New York", timeZone: TimeZone(identifier: "America/New_York")!),
            Location(cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!),
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
