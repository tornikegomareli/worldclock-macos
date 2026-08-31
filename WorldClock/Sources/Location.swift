import Foundation

/// A saved entry in the user's list. Hardcoded defaults until the City
/// database and LocationsStore arrive in later issues.
struct Location: Identifiable {
    let cityName: String
    let timeZone: TimeZone

    var id: String { timeZone.identifier }

    static let defaults = [
        Location(cityName: "Tbilisi", timeZone: TimeZone(identifier: "Asia/Tbilisi")!),
        Location(cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!),
        Location(cityName: "New York", timeZone: TimeZone(identifier: "America/New_York")!),
        Location(cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!),
    ]
}
