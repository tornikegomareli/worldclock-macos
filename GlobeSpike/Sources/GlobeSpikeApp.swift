import SwiftUI

/// Throwaway spike for issue #14 — never merged. One question: does
/// CustomMaterial work inside RealityView on macOS with acceptable quality
/// and performance?
@main
struct GlobeSpikeApp: App {
    var body: some Scene {
        WindowGroup("Globe Spike") {
            GlobeSpikeView()
                .frame(minWidth: 700, minHeight: 560)
        }
    }
}
