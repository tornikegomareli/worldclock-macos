// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    // Dynamic frameworks so the app and the app-hosted test bundle share one
    // copy of each module (static linking duplicates Dependencies' classes).
    productTypes: [
        "Dependencies": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ConcurrencyExtras": .framework,
        "IssueReporting": .framework,
        "XCTestDynamicOverlay": .framework,
    ]
)
#endif

let package = Package(
    name: "WorldClock",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    ]
)
