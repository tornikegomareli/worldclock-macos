import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// The global open/close-Panel shortcut. Default ⌥Space; user changes
    /// persist via the KeyboardShortcuts library.
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

/// Owns the menu-bar NSStatusItem and routes clicks to the Panel: left click
/// (or the global shortcut) toggles it, right click opens the menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let panelController = PanelController()
    private var shortcutWindow: NSWindow?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = Self.makeTiltedEarthIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        panelController.toggle(under: button)
    }

    // MARK: Right-click menu

    private func showMenu() {
        let menu = NSMenu()
        let shortcutItem = NSMenuItem(
            title: "Set Shortcut…",
            action: #selector(openShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit WorldClock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Unset so the next left click toggles the Panel instead of the menu.
        statusItem.menu = nil
    }

    @objc private func openShortcutSettings() {
        if shortcutWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "WorldClock Shortcut"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: ShortcutSettingsView())
            shortcutWindow = window
        }
        shortcutWindow?.center()
        shortcutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
