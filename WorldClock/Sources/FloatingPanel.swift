import AppKit

/// Borderless panel that can become key (needed to receive Esc) and closes on Esc.
@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        if event.keyCode == escapeKeyCode {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
