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
        ),
        .remote(
            url: "https://github.com/sparkle-project/Sparkle",
            requirement: .exact("2.9.6")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "CODE_SIGN_IDENTITY": "-",
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "SPARKLE_PUBLIC_KEY": "",
            "WORLD_CLOCK_WEATHERKIT_ENTITLEMENTS": "",
            "WORLD_CLOCK_WEATHERKIT_PROFILE": "",
            "ENABLE_HARDENED_RUNTIME": "YES",
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
                "LSApplicationCategoryType": "public.app-category.utilities",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "SUFeedURL": "https://github.com/tornikegomareli/worldclock-macos/releases/latest/download/appcast.xml",
                "SUPublicEDKey": "$(SPARKLE_PUBLIC_KEY)",
                "SUEnableAutomaticChecks": false,
                "SUAutomaticallyUpdate": false,
                "SUEnableSystemProfiling": false,
                "SURequireSignedFeed": true,
                "SUVerifyUpdateBeforeExtraction": true,
                "NSLocationUsageDescription": "WorldClock uses your location to choose the nearest Home city. If weather is enabled, that city's coordinates are sent to Apple Weather.",
                "NSLocationWhenInUseUsageDescription": "WorldClock uses your location to choose the nearest Home city. If weather is enabled, that city's coordinates are sent to Apple Weather.",
            ]),
            buildableFolders: [
                "WorldClock/Sources",
                "WorldClock/Resources",
            ],
            dependencies: [
                .external(name: "Dependencies"),
                .package(product: "KeyboardShortcuts"),
                .package(product: "Sparkle"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
                "CODE_SIGN_ENTITLEMENTS": "$(WORLD_CLOCK_WEATHERKIT_ENTITLEMENTS)",
                "PROVISIONING_PROFILE_SPECIFIER": "$(WORLD_CLOCK_WEATHERKIT_PROFILE)",
            ])
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
