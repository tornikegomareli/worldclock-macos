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
    var isCommandSearching = false
    var commandQuery = ""

    /// True while the Globe has taken over — rows scale outward and dim,
    /// and animate back when the Globe returns.
    var isGlobePresented = false

    var isAnyOverlayOpen: Bool { isSearching || isCommandSearching }

    func dismissOverlays() {
        isSearching = false
        searchQuery = ""
        isCommandSearching = false
        commandQuery = ""
    }
}

/// Owns the floating Panel: opens it anchored under the status item, closes on focus loss.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 320, height: 360)

    private let panel: FloatingPanel
    let engine = TimeEngine()
    let store = LocationsStore(storageDirectory: LocationsStore.liveStorageDirectory)
    private let state = PanelState()
    let databaseLoader = CityDatabaseLoader()
    private let keyRouter = PanelKeyRouter()
    private let settings: SettingsStore
    private let weatherStore = WeatherStore(provider: WeatherKitProvider())
    private let greetingProvider = try? GreetingProvider.loadBundled()

    /// Set by StatusItemController; ⌘K's Settings command opens its window.
    var openSettingsHandler: (() -> Void)?

    /// The Globe shares this controller's TimeEngine (ADR-0001).
    private(set) lazy var globeController: GlobeWindowController = {
        let controller = GlobeWindowController(
            engine: engine, store: store, settings: settings,
            databaseLoader: databaseLoader,
            onAddCity: { [weak self] city in self?.execute(.addLocation(city)) }
        )
        controller.onClose = { [weak self] in
            guard let self, let button = statusButton?() else { return }
            open(under: button)
            withAnimation(settings.animation(.easeOut(duration: 0.2))) {
                self.state.isGlobePresented = false
            }
        }
        return controller
    }()

    /// How the Panel finds its anchor when the Globe hands control back.
    var statusButton: (() -> NSStatusBarButton?)?

    init(settings: SettingsStore) {
        self.settings = settings
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
            rootView: PanelContentView(
                engine: engine, store: store, state: state,
                databaseLoader: databaseLoader, settings: settings,
                weatherStore: weatherStore, greetingProvider: greetingProvider,
                onCommand: { [weak self] in self?.execute($0) }
            )
        )
        registerKeys()
        engine.startTicking()
        databaseLoader.load { [weak self] database in
            guard let self else { return }
            // Give timezone-only Locations (like the seeded Home) real
            // coordinates so their Day Lines stop degrading to the equator.
            store.backfillCityDetails { location in
                database.search(location.cityName, at: engine.globalInstant)
                    .first { $0.timeZone == location.timeZone.identifier }
                    .map { (latitude: $0.latitude, longitude: $0.longitude, country: $0.country) }
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
        keyRouter.bind(.character("u")) { [weak self] in self?.toggleOffsetMode() }
        keyRouter.bind(.commandCharacter("k")) { [weak self] in
            self?.state.isCommandSearching = true
        }
        keyRouter.bind(.character(" ")) { [weak self] in
            self?.presentGlobe()
        }
        panel.onKeyEvent = { [weak self] event in
            self?.keyRouter.handle(event) ?? false
        }
    }

    /// The Panel half of the Panel↔Globe transition: rows translate outward
    /// and dim, then the Globe expands out of the Panel's frame; closing
    /// reverses both.
    private func presentGlobe() {
        guard !globeController.isVisible else {
            globeController.close()
            return
        }
        let frame = panel.frame
        withAnimation(settings.animation(.easeOut(duration: 0.15))) {
            state.isGlobePresented = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(self.settings.prefersCrossfade ? 60 : 140))
            self.panel.close()
            self.globeController.open(from: frame)
        }
    }

    private func performEscapeStep() {
        let step = PanelKeyLogic.escapeStep(
            isSearching: state.isAnyOverlayOpen,
            isInspecting: state.inspectedLocationID != nil,
            timeState: engine.state,
            hasSelection: state.selectedLocationID != nil
        )
        switch step {
        case .cancelSearch:
            state.dismissOverlays()
        case .closeInspection:
            withAnimation(settings.animation(.easeInOut(duration: 0.15))) { state.inspectedLocationID = nil }
        case .returnToNow:
            returnToNowAnimated()
        case .clearSelection:
            state.selectedLocationID = nil
        case .closePanel:
            panel.close()
        }
    }

    private func moveSelection(_ direction: PanelKeyLogic.SelectionDirection) {
        guard !state.isAnyOverlayOpen else { return }
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
        withAnimation(settings.animation(.easeInOut(duration: 0.15))) {
            state.inspectedLocationID = id
        }
    }

    private func removeSelectedLocation() {
        guard let id = state.selectedLocationID else { return }
        remove(locationID: id)
    }

    private func remove(locationID id: Location.ID) {
        let nextSelection = state.selectedLocationID == id
            ? PanelKeyLogic.selectionAfterRemoval(of: id, from: store.locations)
            : state.selectedLocationID
        store.remove(id: id)
        // The store refuses to remove the last Location; keep selection there.
        state.selectedLocationID = store.locations.contains { $0.id == id }
            ? state.selectedLocationID
            : nextSelection
        if state.inspectedLocationID == id, !store.locations.contains(where: { $0.id == id }) {
            setInspection(nil)
        }
    }

    /// Swap back to the list first, then insert on the next tick so the new
    /// Location visibly animates into the on-screen list.
    private func addAnimated(_ city: City) {
        guard let zone = TimeZone(identifier: city.timeZone) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(settings.animation(.spring(duration: 0.35))) {
                store.add(
                    Location(
                        cityName: city.name, timeZone: zone,
                        latitude: city.latitude, longitude: city.longitude,
                        country: city.country
                    )
                )
            }
        }
    }

    /// Executes a ⌘K command and dismisses the overlay. Also the single add
    /// path for the city-search overlay, so both surfaces animate identically.
    func execute(_ command: PanelCommand) {
        state.dismissOverlays()
        switch command {
        case let .addLocation(city):
            addAnimated(city)
        case let .showLocation(location):
            state.selectedLocationID = location.id
        case let .removeLocation(location):
            remove(locationID: location.id)
        case .openGlobe:
            presentGlobe()
        case .switchToUTCMode:
            settings.offsetMode = .utc
        case .switchToRelativeMode:
            settings.offsetMode = .relative
        case .returnToNow:
            returnToNowAnimated()
        case .openSettings:
            openSettingsHandler?()
        }
    }

    private func toggleOffsetMode() {
        settings.offsetMode = settings.offsetMode == .relative ? .utc : .relative
    }

    private func returnToNowAnimated() {
        guard engine.state != .now else { return }
        withAnimation(settings.animation(.spring(duration: 0.4))) { engine.returnToNow() }
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
        if settings.showWeather {
            // Fire-and-forget: weather never blocks or delays time rendering.
            let locations = store.locations
            Task { await weatherStore.refresh(locations) }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.close()
    }
}
