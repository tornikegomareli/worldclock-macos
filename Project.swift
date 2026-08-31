import ProjectDescription

let project = Project(
    name: "WorldClock",
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
                "WorldClock/Sources"
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
                .target(name: "WorldClock")
            ]
        ),
    ]
)
