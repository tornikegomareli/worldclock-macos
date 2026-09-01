import ProjectDescription

let project = Project(
    name: "WorldClock",
    // Xcode-native SPM integration: Tuist's synthesized resource bundles
    // mis-type this package's .lproj strings files as plists and fail
    // validation, so Xcode's own package pipeline builds it instead.
    packages: [
        .remote(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            requirement: .upToNextMajor(from: "2.0.0")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "CODE_SIGN_IDENTITY": "-",
        ]
    ),
    targets: [
        .target(
            name: "WorldClock",
            destinations: .macOS,
            product: .app,
            bundleId: "com.tornikegomareli.WorldClock",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "NSLocationUsageDescription": "WorldClock keeps your Home Location on the nearest city while you travel. Your location never leaves this Mac.",
                "NSLocationWhenInUseUsageDescription": "WorldClock keeps your Home Location on the nearest city while you travel. Your location never leaves this Mac.",
            ]),
            buildableFolders: [
                "WorldClock/Sources",
                "WorldClock/Resources",
            ],
            dependencies: [
                .external(name: "Dependencies"),
                .package(product: "KeyboardShortcuts"),
            ]
        ),
        // Spike target for issue #14 — lives only on prototype/globe-spike.
        .target(
            name: "GlobeSpike",
            destinations: .macOS,
            product: .app,
            bundleId: "com.tornikegomareli.GlobeSpike",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: [
                "GlobeSpike/Sources/**",
                "WorldClock/Sources/Astronomy/Astronomy.swift",
            ],
            resources: ["GlobeSpike/Resources/**"]
        ),
        .target(
            name: "WorldClockTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tornikegomareli.WorldClockTests",
            deploymentTargets: .macOS("15.0"),
            buildableFolders: [
                "WorldClockTests"
            ],
            dependencies: [
                .target(name: "WorldClock"),
                .external(name: "Dependencies"),
                .external(name: "Clocks"),
                .external(name: "ConcurrencyExtras"),
            ]
        ),
    ]
)
