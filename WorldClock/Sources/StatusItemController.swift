import AppKit

/// Owns the menu-bar NSStatusItem and routes clicks to the Panel.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let panelController = PanelController()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.makeTiltedEarthIcon()
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panelController.toggle(under: button)
    }

    /// Template image of an Earth glyph rotated to the planet's axial tilt (23.4°).
    private static func makeTiltedEarthIcon() -> NSImage? {
        guard let globe = NSImage(
            systemSymbolName: "globe.americas.fill",
            accessibilityDescription: "WorldClock"
        ) else { return nil }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: -23.4 * .pi / 180)
            context.translateBy(x: -rect.midX, y: -rect.midY)
            globe.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
