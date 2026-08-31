import AppKit

/// Borderless panel that can become key (needed to receive Esc) and routes
/// keys at window level — SwiftUI's focus-based key commands don't engage
/// inside a nonactivating panel. Keys reach here only when no text field
/// consumed them first.
@MainActor
final class FloatingPanel: NSPanel {
    /// Return true when the key was handled (e.g. the search overlay was
    /// open and is now dismissed, or Time Travel returned to Now); false
    /// lets the panel close instead.
    var onEscape: (() -> Bool)?
    var onDeleteKey: (() -> Void)?
    var onAddKey: (() -> Void)?
    var onNowKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    /// Shortcuts are intercepted before the responder chain — the List's
    /// type-select would otherwise swallow letters that match a row (N for
    /// "New York"). While a text field is editing, everything passes through
    /// so typing works; the field editor routes its own Esc/Return.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !(firstResponder is NSText), handleShortcut(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let escapeKeyCode: UInt16 = 53
        let deleteKeyCode: UInt16 = 51
        switch event.keyCode {
        case escapeKeyCode:
            if onEscape?() != true {
                close()
            }
            return true
        case deleteKeyCode where onDeleteKey != nil:
            onDeleteKey?()
            return true
        default:
            let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            guard !hasModifiers, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if key == "a", let onAddKey {
                onAddKey()
                return true
            }
            if key == "n", let onNowKey {
                onNowKey()
                return true
            }
            return false
        }
    }
}
