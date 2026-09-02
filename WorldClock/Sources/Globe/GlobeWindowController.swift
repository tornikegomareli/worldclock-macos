import AppKit
import SwiftUI

/// A titled window whose Esc and Space route back to the Panel flow.
@MainActor
final class GlobeWindow: NSWindow {
    var onEscapeOrSpace: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        let spaceKeyCode: UInt16 = 49
        if event.type == .keyDown,
           event.keyCode == escapeKeyCode || event.keyCode == spaceKeyCode,
           !(firstResponder is NSText) {
            onEscapeOrSpace?()
            return
        }
        super.sendEvent(event)
    }
}

/// Owns the Globe window: same TimeEngine as the Panel, so both surfaces
/// always render the one Global Instant (ADR-0001).
@MainActor
final class GlobeWindowController {
    private let engine: TimeEngine
    private var window: GlobeWindow?
    private var sceneController: GlobeSceneController?

    /// Called when the Globe closes so the Panel can come back.
    var onClose: (() -> Void)?

    init(engine: TimeEngine) {
        self.engine = engine
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        if window == nil {
            let sceneController = GlobeSceneController(engine: engine)
            let window = GlobeWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Globe"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(rootView: GlobeView(controller: sceneController))
            window.onEscapeOrSpace = { [weak self] in self?.close() }
            window.center()
            self.window = window
            self.sceneController = sceneController
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        sceneController?.installScrollZoomMonitor()
    }

    func close() {
        sceneController?.removeScrollZoomMonitor()
        window?.close()
        onClose?()
    }
}
