import SwiftUI

/// Placeholder Panel content; real Location list arrives in later issues.
struct PanelContentView: View {
    var body: some View {
        Text("WorldClock")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
