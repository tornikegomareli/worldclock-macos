import AppKit
import SwiftUI

/// Owns the floating Panel: opens it anchored under the status item, closes on focus loss.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 320, height: 360)

    private let panel: FloatingPanel
    private let engine = TimeEngine()

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: PanelContentView(engine: engine))
        engine.startTicking()
    }

    func toggle(under button: NSStatusBarButton) {
        if panel.isVisible {
            panel.close()
        } else {
            open(under: button)
        }
    }

    private func open(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchorFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? .zero
        let frame = PanelPlacement.frame(
            anchoredUnder: anchorFrame,
            panelSize: Self.panelSize,
            screenFrame: screenFrame
        )
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.close()
    }
}
