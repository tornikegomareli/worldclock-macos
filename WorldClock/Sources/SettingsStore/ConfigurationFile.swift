import Foundation

/// The export/import payload: the user's Locations plus every preference.
struct ConfigurationFile: Codable {
    let locations: [Location]
    let settings: SettingsSnapshot

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(locations: [Location], settings: SettingsSnapshot) {
        self.locations = locations
        self.settings = settings
    }

    init(decoding data: Data) throws {
        self = try JSONDecoder().decode(ConfigurationFile.self, from: data)
    }
}
