import AppKit

/// Borderless panel that can become key (needed to receive Esc) and routes
/// keys at window level — SwiftUI's focus-based key commands don't engage
/// inside a nonactivating panel. Keys reach here only when no text field
/// consumed them first.
@MainActor
final class FloatingPanel: NSPanel {
    /// Return true when the key was handled (e.g. the search overlay was
    /// open and is now dismissed); false lets the panel close instead.
    var onEscape: (() -> Bool)?
    var onDeleteKey: (() -> Void)?
    var onAddKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        let deleteKeyCode: UInt16 = 51
        switch event.keyCode {
        case escapeKeyCode:
            if onEscape?() != true {
                close()
            }
        case deleteKeyCode where onDeleteKey != nil:
            onDeleteKey?()
        default:
            let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            if !hasModifiers, event.charactersIgnoringModifiers?.lowercased() == "a", let onAddKey {
                onAddKey()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
