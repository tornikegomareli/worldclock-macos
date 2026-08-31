import AppKit

/// Borderless panel that can become key (needed to receive Esc), closes on
/// Esc, and routes the Delete key at window level — SwiftUI's focus-based key
/// commands don't engage inside a nonactivating panel.
@MainActor
final class FloatingPanel: NSPanel {
    var onDeleteKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        let deleteKeyCode: UInt16 = 51
        switch event.keyCode {
        case escapeKeyCode:
            close()
        case deleteKeyCode where onDeleteKey != nil:
            onDeleteKey?()
        default:
            super.keyDown(with: event)
        }
    }
}
