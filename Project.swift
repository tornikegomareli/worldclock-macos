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
