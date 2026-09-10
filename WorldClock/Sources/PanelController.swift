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

    /// True while the Globe has expanded in place of the lanes — the panel
    /// widens and the list gives way to the Earth.
    var isGlobePresented = false

    var isAnyOverlayOpen: Bool { isSearching || isCommandSearching }

    func dismissOverlays() {
        isSearching = false
        searchQuery = ""
        isCommandSearching = false
        commandQuery = ""
    }
}

/// Owns the floating Panel: opens it anchored under the status item, closes on
/// focus loss, and resizes it in place — for content changes and for the
/// Globe expanding inside it.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let hosting: NSHostingController<PanelContentView>
    let engine = TimeEngine()
    let store = LocationsStore(storageDirectory: LocationsStore.liveStorageDirectory)
    private let state = PanelState()
    let databaseLoader = CityDatabaseLoader()
    private let keyRouter = PanelKeyRouter()
    private let settings: SettingsStore
    private let weatherStore = WeatherStore(provider: WeatherKitProvider())
    private let greetingProvider = try? GreetingProvider.loadBundled()

    /// The Globe shares this controller's TimeEngine (ADR-0001) and lives
    /// inside the Panel; the scene controller persists across presents so the
    /// camera remembers its orientation.
    private let globeScene: GlobeSceneController
    private let globeState = GlobeState()

    /// Set by StatusItemController; ⌘K's Settings command opens its window.
    var openSettingsHandler: (() -> Void)?

    /// Where the Panel anchors — kept so in-place resizes stay under the
    /// status item.
    private var anchorFrame: NSRect?
    private var anchorScreenFrame: NSRect?

    init(settings: SettingsStore) {
        self.settings = settings
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        globeScene = GlobeSceneController(engine: engine, store: store, state: globeState)
        var onCommand: (PanelCommand) -> Void = { _ in }
        hosting = NSHostingController(
            rootView: PanelContentView(
                engine: engine, store: store, state: state,
                databaseLoader: databaseLoader, settings: settings,
                weatherStore: weatherStore, greetingProvider: greetingProvider,
                globeScene: globeScene, globeState: globeState,
                onCommand: { onCommand($0) }
            )
        )
        super.init()
        onCommand = { [weak self] in self?.execute($0) }
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = hosting
        registerKeys()
        trackContentSize()
        engine.startTicking()
        globeScene.prewarm()
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
        keyRouter.bind(.leftArrow) { [weak self] in self?.nudge(-1) }
        keyRouter.bind(.rightArrow) { [weak self] in self?.nudge(1) }
        keyRouter.bind(.returnKey) { [weak self] in self?.toggleInspection() }
        keyRouter.bind(.delete) { [weak self] in self?.removeSelectedLocation() }
        keyRouter.bind(.character("a")) { [weak self] in
            guard let self, !state.isGlobePresented else { return }
            state.isSearching = true
        }
        keyRouter.bind(.character("n")) { [weak self] in self?.returnToNowAnimated() }
        keyRouter.bind(.character("u")) { [weak self] in self?.toggleOffsetMode() }
        keyRouter.bind(.character("j")) { [weak self] in
            guard let self, state.isGlobePresented else { return }
            globeState.isJumping = true
        }
        keyRouter.bind(.commandCharacter("k")) { [weak self] in
            guard let self, !state.isGlobePresented else { return }
            state.isCommandSearching = true
        }
        keyRouter.bind(.character(" ")) { [weak self] in self?.toggleGlobe() }
        panel.onKeyEvent = { [weak self] event in
            self?.keyRouter.handle(event) ?? false
        }
    }

    /// ←/→ nudge Time Travel by an hour (Shift: 15 minutes), clamped to the
    /// same ±7 days scrubbing has.
    private func nudge(_ direction: Double) {
        guard !state.isAnyOverlayOpen else { return }
        let fine = NSEvent.modifierFlags.contains(.shift)
        let delta = direction * (fine ? 15 : 60) * 60
        let target = ScrubberLogic.clamped(
            engine.globalInstant.addingTimeInterval(delta),
            around: engine.now
        )
        withAnimation(settings.animation(.easeOut(duration: 0.2))) {
            engine.simulate(target)
        }
    }

    // MARK: Globe — expands in place of the lanes.

    private func toggleGlobe() {
        setGlobePresented(!state.isGlobePresented)
    }

    private func setGlobePresented(_ presented: Bool) {
        guard state.isGlobePresented != presented else { return }
        if presented {
            state.dismissOverlays()
        } else {
            globeState.cancelJump()
            globeState.inspection = nil
            globeScene.removeScrollZoomMonitor()
        }
        state.isGlobePresented = presented
    }

    private func performEscapeStep() {
        if state.isGlobePresented {
            switch globeState.escapeStep {
            case .cancelJump:
                globeState.cancelJump()
            case .closeInspection:
                globeState.inspection = nil
            case .closeGlobe:
                setGlobePresented(false)
            }
            return
        }
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
        guard !state.isAnyOverlayOpen, !state.isGlobePresented else { return }
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
        guard !state.isGlobePresented, let selected = state.selectedLocationID else { return }
        setInspection(state.inspectedLocationID == selected ? nil : selected)
    }

    private func setInspection(_ id: Location.ID?) {
        guard state.inspectedLocationID != id else { return }
        withAnimation(settings.animation(.easeInOut(duration: 0.15))) {
            state.inspectedLocationID = id
        }
    }

    private func removeSelectedLocation() {
        guard !state.isGlobePresented, let id = state.selectedLocationID else { return }
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
                state.selectedLocationID = city.timeZone
            }
        }
    }

    /// Executes a ⌘K command and dismisses the overlay. Also the single add
    /// path for the city-search overlay, so both surfaces animate identically.
    func execute(_ command: PanelCommand) {
        state.dismissOverlays()
        switch command {
        case let .addLocation(city):
            if let existing = store.locations.first(where: { $0.id == city.timeZone }) {
                state.selectedLocationID = existing.id
            } else {
                addAnimated(city)
            }
        case let .showLocation(location):
            state.selectedLocationID = location.id
        case let .removeLocation(location):
            remove(locationID: location.id)
        case .openGlobe:
            toggleGlobe()
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

    // MARK: Sizing — the panel always fits its content, in place.

    /// Resizes whenever anything that changes the content's height mutates:
    /// the Location list, inspection, the overlays, or the Globe expanding.
    private func trackContentSize() {
        let wasGlobePresented = state.isGlobePresented
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = store.locations.count
            _ = state.inspectedLocationID
            _ = state.isSearching
            _ = state.isCommandSearching
            _ = state.isGlobePresented
            _ = settings.showWeather
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.resizeToFit(
                    animated: true,
                    duration: wasGlobePresented == self.state.isGlobePresented ? 0.3 : 0.22
                )
                self.trackContentSize()
            }
        }
    }

    private func fittingFrame() -> NSRect? {
        guard let anchorFrame, let anchorScreenFrame else { return nil }
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        let size = NSSize(
            width: fitting.width,
            height: min(max(fitting.height, 200), anchorScreenFrame.height - 20)
        )
        return PanelPlacement.frame(
            anchoredUnder: anchorFrame,
            panelSize: size,
            screenFrame: anchorScreenFrame
        )
    }

    private func resizeToFit(animated: Bool, duration: TimeInterval = 0.3) {
        guard panel.isVisible else { return }
        // Let SwiftUI process the state change before measuring.
        Task { @MainActor in
            await Task.yield()
            self.applyFittingFrame(animated: animated, duration: duration)
        }
    }

    private func applyFittingFrame(animated: Bool, duration: TimeInterval) {
        guard let frame = fittingFrame(), frame != panel.frame else { return }
        if animated, settings.animationsEnabled, !settings.prefersCrossfade {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Presentation

    func toggle(under button: NSStatusBarButton) {
        if panel.isVisible {
            panel.close()
        } else {
            open(under: button)
        }
    }

    private func open(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        anchorFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreenFrame = buttonWindow.screen?.visibleFrame ?? .zero
        if let frame = fittingFrame() {
            panel.setFrame(frame, display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        // Measured before display the first fit can be stale; settle it.
        resizeToFit(animated: false)
        if settings.showWeather {
            // Fire-and-forget: weather never blocks or delays time rendering.
            let locations = store.locations
            Task { await weatherStore.refresh(locations) }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        // The Globe never survives a close: the panel reopens as the list.
        globeScene.removeScrollZoomMonitor()
        globeState.cancelJump()
        globeState.inspection = nil
        state.isGlobePresented = false
    }
}
