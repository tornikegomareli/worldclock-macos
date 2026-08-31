import Foundation

/// An entry in the bundled offline city database (GeoNames cities15000):
/// the sole timezone source for a Location.
struct City: Codable, Equatable, Identifiable {
    let name: String
    let asciiName: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    let alternates: [String]
    let population: Int

    var id: String { "\(name)|\(country)|\(latitude)|\(longitude)" }
}
