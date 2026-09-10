import AppKit

/// Borderless panel that can become key (needed to receive keys at all) and
/// routes key events through the PanelKeyRouter ahead of the responder chain
/// — SwiftUI's focus-based key commands don't engage inside a nonactivating
/// panel, and the List's type-select would swallow letters that match a row
/// (N for "New York"). While a text field is editing, everything passes
/// through so typing works; the field editor routes its own Esc/Return.
@MainActor
final class FloatingPanel: NSPanel {
    /// Return true when the event was consumed.
    var onKeyEvent: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // Menu-bar apps have no Edit menu to route standard text shortcuts.
        if event.type == .keyDown, let editor = firstResponder as? NSText,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                editor.selectAll(nil)
                return
            case "c":
                editor.copy(nil)
                return
            case "x":
                editor.cut(nil)
                return
            case "v":
                editor.paste(nil)
                return
            default: break
            }
        }
        if event.type == .keyDown, !(firstResponder is NSText), onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}
