import AppKit

/// The Panel's single key-routing table. Every shortcut registers here
/// (see PanelController.registerKeys), and FloatingPanel feeds it key events
/// ahead of the responder chain.
@MainActor
final class PanelKeyRouter {
    enum Key: Hashable {
        case escape
        case delete
        case returnKey
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case character(Character)
        case commandCharacter(Character)

        private static let escapeKeyCode: UInt16 = 53
        private static let deleteKeyCode: UInt16 = 51
        private static let forwardDeleteKeyCode: UInt16 = 117
        private static let returnKeyCode: UInt16 = 36
        private static let upArrowKeyCode: UInt16 = 126
        private static let downArrowKeyCode: UInt16 = 125
        private static let leftArrowKeyCode: UInt16 = 123
        private static let rightArrowKeyCode: UInt16 = 124

        static func from(_ event: NSEvent) -> Key? {
            switch event.keyCode {
            case escapeKeyCode: return .escape
            case deleteKeyCode, forwardDeleteKeyCode: return .delete
            case returnKeyCode: return .returnKey
            case upArrowKeyCode: return .upArrow
            case downArrowKeyCode: return .downArrow
            case leftArrowKeyCode: return .leftArrow
            case rightArrowKeyCode: return .rightArrow
            default:
                guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                      let character = characters.first,
                      characters.count == 1
                else { return nil }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if modifiers == .command {
                    return .commandCharacter(character)
                }
                guard modifiers.isEmpty else { return nil }
                return .character(character)
            }
        }
    }

    private var bindings: [Key: () -> Void] = [:]

    func bind(_ key: Key, to action: @escaping () -> Void) {
        bindings[key] = action
    }

    /// Returns true when a binding consumed the event.
    func handle(_ event: NSEvent) -> Bool {
        guard let key = Key.from(event), let action = bindings[key] else { return false }
        action()
        return true
    }
}
