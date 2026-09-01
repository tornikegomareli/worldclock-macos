import AppKit
import Observation
import SwiftUI

/// The Panel's UI state — selection, inspection, and the search overlay —
/// shared between the SwiftUI content and the window-level key handlers.
@MainActor
@Observable
final class PanelState {
    var selectedLocationID: Location.ID?
    var inspectedLocationID: Location.ID?
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
    private let keyRouter = PanelKeyRouter()

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
        registerKeys()
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

    // MARK: Key routing — the one registration point for Panel shortcuts.

    private func registerKeys() {
        keyRouter.bind(.escape) { [weak self] in self?.performEscapeStep() }
        keyRouter.bind(.upArrow) { [weak self] in self?.moveSelection(.up) }
        keyRouter.bind(.downArrow) { [weak self] in self?.moveSelection(.down) }
        keyRouter.bind(.returnKey) { [weak self] in self?.toggleInspection() }
        keyRouter.bind(.delete) { [weak self] in self?.removeSelectedLocation() }
        keyRouter.bind(.character("a")) { [weak self] in self?.state.isSearching = true }
        keyRouter.bind(.character("n")) { [weak self] in self?.returnToNowAnimated() }
        panel.onKeyEvent = { [weak self] event in
            self?.keyRouter.handle(event) ?? false
        }
    }

    private func performEscapeStep() {
        let step = PanelKeyLogic.escapeStep(
            isSearching: state.isSearching,
            isInspecting: state.inspectedLocationID != nil,
            timeState: engine.state,
            hasSelection: state.selectedLocationID != nil
        )
        switch step {
        case .cancelSearch:
            state.cancelSearch()
        case .closeInspection:
            withAnimation(.easeInOut(duration: 0.15)) { state.inspectedLocationID = nil }
        case .returnToNow:
            returnToNowAnimated()
        case .clearSelection:
            state.selectedLocationID = nil
        case .closePanel:
            panel.close()
        }
    }

    private func moveSelection(_ direction: PanelKeyLogic.SelectionDirection) {
        guard !state.isSearching else { return }
        let moved = PanelKeyLogic.movedSelection(
            from: state.selectedLocationID,
            by: direction,
            in: store.locations
        )
        state.selectedLocationID = moved
        // Inspection belongs to the selected Location; it never lingers on
        // a row the selection has left.
        if state.inspectedLocationID != moved {
            setInspection(nil)
        }
    }

    private func toggleInspection() {
        guard let selected = state.selectedLocationID else { return }
        setInspection(state.inspectedLocationID == selected ? nil : selected)
    }

    private func setInspection(_ id: Location.ID?) {
        guard state.inspectedLocationID != id else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            state.inspectedLocationID = id
        }
    }

    private func removeSelectedLocation() {
        guard let id = state.selectedLocationID else { return }
        let nextSelection = PanelKeyLogic.selectionAfterRemoval(of: id, from: store.locations)
        store.remove(id: id)
        // The store refuses to remove the last Location; keep selection there.
        state.selectedLocationID = store.locations.contains { $0.id == id } ? id : nextSelection
        if state.inspectedLocationID == id {
            setInspection(nil)
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
