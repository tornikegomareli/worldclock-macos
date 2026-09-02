import AppKit
import KeyboardShortcuts
import Observation
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
    private let settings = SettingsStore()
    private let panelController: PanelController
    private var homeLocationUpdater: HomeLocationUpdater?
    private var settingsWindow: NSWindow?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panelController = PanelController(settings: settings)
        super.init()
        panelController.openSettingsHandler = { [weak self] in self?.openSettings() }
        panelController.statusButton = { [weak self] in self?.statusItem.button }
        homeLocationUpdater = HomeLocationUpdater(
            settings: settings,
            store: panelController.store,
            databaseLoader: panelController.databaseLoader
        )
        if let button = statusItem.button {
            button.image = Self.makeTiltedEarthIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        updateMenuBarTitle()
    }

    /// Renders the optional menu-bar time (a chosen Location's Local Time of
    /// the one Global Instant — ADR-0001) and re-arms observation so it
    /// follows ticks, scrubbing, and the Settings picker. Icon-only default.
    private func updateMenuBarTitle() {
        withObservationTracking { [weak self] in
            guard let self, let button = statusItem.button else { return }
            let engine = panelController.engine
            let title: String
            if let id = settings.menuBarLocationID,
               let location = panelController.store.locations.first(where: { $0.id == id }) {
                let localTime = LocalTime(of: engine.globalInstant, in: location.timeZone)
                title = " " + TimeFormatting.timeString(localTime, clockFormat: settings.resolvedClockFormat)
            } else {
                title = ""
            }
            if button.title != title {
                statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
                button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
                button.title = title
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateMenuBarTitle() }
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
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit WorldClock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Unset so the next left click toggles the Panel instead of the menu.
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "WorldClock Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(settings: settings, store: panelController.store)
            )
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
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
