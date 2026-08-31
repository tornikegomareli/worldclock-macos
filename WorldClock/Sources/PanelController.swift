import AppKit
import Observation
import SwiftUI

/// The Panel's UI state — selection and the search overlay — shared between
/// the SwiftUI content and the window-level key handlers.
@MainActor
@Observable
final class PanelState {
    var selectedLocationID: Location.ID?
    var isSearching = false
    var searchQuery = ""

    func cancelSearch() {
        isSearching = false
        searchQuery = ""
    }
}

/// Owns the floating Panel: opens it anchored under the status item, closes on focus loss.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 320, height: 360)

    private let panel: FloatingPanel
    private let engine = TimeEngine()
    private let store = LocationsStore(storageDirectory: LocationsStore.liveStorageDirectory)
    private let state = PanelState()
    private let databaseLoader = CityDatabaseLoader()

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(
            rootView: PanelContentView(engine: engine, store: store, state: state, databaseLoader: databaseLoader)
        )
        panel.onDeleteKey = { [weak self] in
            guard let self, let id = state.selectedLocationID else { return }
            store.remove(id: id)
            state.selectedLocationID = nil
        }
        panel.onEscape = { [weak self] in
            guard let self else { return false }
            if state.isSearching {
                state.cancelSearch()
                return true
            }
            // CONTEXT.md: Esc returns the Time State to Now; the panel closes
            // only from Now mode.
            if engine.state != .now {
                returnToNowAnimated()
                return true
            }
            return false
        }
        panel.onAddKey = { [weak self] in
            self?.state.isSearching = true
        }
        panel.onNowKey = { [weak self] in
            self?.returnToNowAnimated()
        }
        engine.startTicking()
        databaseLoader.load { [weak self] database in
            guard let self else { return }
            // Give timezone-only Locations (like the seeded Home) real
            // coordinates so their Day Lines stop degrading to the equator.
            store.backfillCoordinates { location in
                database.search(location.cityName, at: engine.globalInstant)
                    .first { $0.timeZone == location.timeZone.identifier }
                    .map { (latitude: $0.latitude, longitude: $0.longitude) }
            }
        }
    }

    private func returnToNowAnimated() {
        guard engine.state != .now else { return }
        withAnimation(.spring(duration: 0.4)) { engine.returnToNow() }
    }

    func toggle(under button: NSStatusBarButton) {
        if panel.isVisible {
            panel.close()
        } else {
            open(under: button)
        }
    }

    private func open(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchorFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? .zero
        let frame = PanelPlacement.frame(
            anchoredUnder: anchorFrame,
            panelSize: Self.panelSize,
            screenFrame: screenFrame
        )
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.close()
    }
}
