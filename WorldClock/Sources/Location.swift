import Foundation

/// A saved entry in the user's list — a city name plus its timezone, until
/// the City database gives Locations a real City reference. Coordinates are
/// optional: a Location seeded from just a timezone has none, and its Day
/// Line degrades to an equatorial approximation.
struct Location: Identifiable, Equatable {
    let cityName: String
    let timeZone: TimeZone
    let latitude: Double?
    let longitude: Double?
    /// ISO country code from the City, for locale-dependent enrichment
    /// like Greetings.
    let country: String?

    init(
        cityName: String,
        timeZone: TimeZone,
        latitude: Double? = nil,
        longitude: Double? = nil,
        country: String? = nil
    ) {
        self.cityName = cityName
        self.timeZone = timeZone
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
    }

    var id: String { timeZone.identifier }
}

/// Persisted as {cityName, timeZoneIdentifier}; an unknown identifier fails
/// decoding, which the store treats as a corrupt file.
extension Location: Codable {
    private enum CodingKeys: String, CodingKey {
        case cityName
        case timeZoneIdentifier
        case latitude
        case longitude
        case country
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cityName = try container.decode(String.self, forKey: .cityName)
        let identifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeZoneIdentifier,
                in: container,
                debugDescription: "Unknown IANA timezone identifier: \(identifier)"
            )
        }
        self.timeZone = timeZone
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        country = try container.decodeIfPresent(String.self, forKey: .country)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cityName, forKey: .cityName)
        try container.encode(timeZone.identifier, forKey: .timeZoneIdentifier)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(country, forKey: .country)
    }
}
