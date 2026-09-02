import RealityKit
import SwiftUI

/// The Globe: the expanded 3D surface rendering the same Global Instant as
/// the Panel, including its sunlight terminator (CONTEXT.md).
struct GlobeView: View {
    let controller: GlobeSceneController

    @State private var setupError: String?

    var body: some View {
        ZStack {
            RealityView { content in
                do {
                    try controller.build(in: content)
                } catch {
                    setupError = "\(error)"
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in controller.orbit(by: value.translation) }
                    .onEnded { _ in controller.endOrbit() }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in controller.magnify(to: value.magnification) }
                    .onEnded { _ in controller.endMagnify() }
            )
            .onAppear { controller.installScrollZoomMonitor() }

            if let setupError {
                Text(setupError)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.black.opacity(0.8))
            }
        }
        .background(.black)
    }
}
