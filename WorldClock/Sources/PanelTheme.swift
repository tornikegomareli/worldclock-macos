import SwiftUI

/// The Meridian design's color tokens. Four palettes: light/dark, each with a
/// Time Travel variant that re-tints the whole panel amber — Time Travel is a
/// temperature, not a banner.
struct PanelTheme: Equatable {
    let background: Color
    let text: Color
    let secondaryText: Color
    let tertiaryText: Color
    let separator: Color
    let hover: Color
    let selection: Color
    let pill: Color
    let accent: Color
    let onAccent: Color
    let night: Color
    let twilight: Color
    let day: Color
    let edge: Color
    let cursor: Color
    let skyDay: Color
    let skyDusk: Color
    let skyNight: Color

    static func resolve(dark: Bool, timeTravel: Bool) -> PanelTheme {
        switch (dark, timeTravel) {
        case (true, false): .dark
        case (true, true): .darkTimeTravel
        case (false, false): .light
        case (false, true): .lightTimeTravel
        }
    }

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    static let dark = PanelTheme(
        background: rgba(28, 28, 31, 0.86),
        text: rgba(245, 245, 247),
        secondaryText: rgba(235, 235, 245, 0.6),
        tertiaryText: rgba(235, 235, 245, 0.52),
        separator: rgba(255, 255, 255, 0.08),
        hover: rgba(255, 255, 255, 0.04),
        selection: rgba(255, 255, 255, 0.09),
        pill: rgba(255, 255, 255, 0.09),
        accent: rgba(158, 194, 248),
        onAccent: rgba(29, 29, 31),
        night: rgba(18, 23, 42),
        twilight: rgba(217, 120, 74),
        day: rgba(235, 221, 176),
        edge: rgba(255, 255, 255, 0.1),
        cursor: rgba(255, 255, 255, 0.85),
        skyDay: rgba(90, 140, 210, 0.55),
        skyDusk: rgba(240, 140, 80, 0.5),
        skyNight: rgba(28, 36, 90, 0.6)
    )

    static let darkTimeTravel = PanelTheme(
        background: rgba(44, 31, 18, 0.9),
        text: rgba(251, 242, 227),
        secondaryText: rgba(255, 236, 208, 0.62),
        tertiaryText: rgba(255, 236, 208, 0.52),
        separator: rgba(255, 205, 150, 0.13),
        hover: rgba(255, 180, 90, 0.06),
        selection: rgba(255, 170, 80, 0.13),
        pill: rgba(255, 190, 110, 0.12),
        accent: rgba(255, 179, 64),
        onAccent: rgba(43, 26, 5),
        night: rgba(34, 27, 36),
        twilight: rgba(238, 137, 70),
        day: rgba(246, 222, 174),
        edge: rgba(255, 190, 110, 0.18),
        cursor: rgba(255, 179, 64),
        skyDay: rgba(90, 140, 210, 0.55),
        skyDusk: rgba(240, 140, 80, 0.5),
        skyNight: rgba(28, 36, 90, 0.6)
    )

    static let light = PanelTheme(
        background: rgba(246, 246, 248, 0.88),
        text: rgba(29, 29, 31),
        secondaryText: rgba(60, 60, 67, 0.6),
        tertiaryText: rgba(60, 60, 67, 0.55),
        separator: rgba(0, 0, 0, 0.08),
        hover: rgba(0, 0, 0, 0.03),
        selection: rgba(0, 0, 0, 0.06),
        pill: rgba(0, 0, 0, 0.06),
        accent: rgba(51, 104, 177),
        onAccent: rgba(255, 255, 255),
        night: rgba(42, 50, 81),
        twilight: rgba(240, 154, 90),
        day: rgba(255, 240, 196),
        edge: rgba(0, 0, 0, 0.08),
        cursor: rgba(0, 0, 0, 0.7),
        skyDay: rgba(130, 180, 240, 0.6),
        skyDusk: rgba(240, 140, 80, 0.5),
        skyNight: rgba(70, 80, 140, 0.35)
    )

    static let lightTimeTravel = PanelTheme(
        background: rgba(255, 241, 222, 0.92),
        text: rgba(58, 40, 16),
        secondaryText: rgba(95, 62, 20, 0.64),
        tertiaryText: rgba(95, 62, 20, 0.55),
        separator: rgba(160, 100, 30, 0.14),
        hover: rgba(230, 140, 40, 0.07),
        selection: rgba(230, 140, 40, 0.14),
        pill: rgba(230, 140, 40, 0.12),
        accent: rgba(194, 98, 10),
        onAccent: rgba(255, 255, 255),
        night: rgba(58, 51, 80),
        twilight: rgba(240, 138, 69),
        day: rgba(255, 235, 186),
        edge: rgba(200, 130, 50, 0.2),
        cursor: rgba(194, 98, 10),
        skyDay: rgba(130, 180, 240, 0.6),
        skyDusk: rgba(240, 140, 80, 0.5),
        skyNight: rgba(70, 80, 140, 0.35)
    )
}
