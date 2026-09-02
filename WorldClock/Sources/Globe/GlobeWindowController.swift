import AppKit
import SwiftUI

/// A titled window routing Esc (walk-back), Space (toggle back to Panel),
/// and J (Jump) ahead of the responder chain, except while typing.
@MainActor
final class GlobeWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onJump: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        let spaceKeyCode: UInt16 = 49
        if event.type == .keyDown, !(firstResponder is NSText) {
            switch event.keyCode {
            case escapeKeyCode:
                onEscape?()
                return
            case spaceKeyCode:
                onSpace?()
                return
            default:
                if event.charactersIgnoringModifiers?.lowercased() == "j",
                   event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    onJump?()
                    return
                }
            }
        }
        super.sendEvent(event)
    }
}

/// Owns the Globe window: same TimeEngine as the Panel, so both surfaces
/// always render the one Global Instant (ADR-0001).
@MainActor
final class GlobeWindowController {
    private let engine: TimeEngine
    private let store: LocationsStore
    private let settings: SettingsStore
    private let databaseLoader: CityDatabaseLoader
    private let onAddCity: (City) -> Void
    private let state = GlobeState()
    private var window: GlobeWindow?
    private var sceneController: GlobeSceneController?

    /// Called when the Globe closes so the Panel can come back.
    var onClose: (() -> Void)?

    init(
        engine: TimeEngine,
        store: LocationsStore,
        settings: SettingsStore,
        databaseLoader: CityDatabaseLoader,
        onAddCity: @escaping (City) -> Void
    ) {
        self.engine = engine
        self.store = store
        self.settings = settings
        self.databaseLoader = databaseLoader
        self.onAddCity = onAddCity
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        if window == nil {
            let sceneController = GlobeSceneController(engine: engine, store: store)
            let window = GlobeWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Globe"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(
                rootView: GlobeView(
                    controller: sceneController, engine: engine, store: store,
                    settings: settings, databaseLoader: databaseLoader,
                    state: state, onAddCity: onAddCity
                )
            )
            window.onEscape = { [weak self] in self?.performEscapeStep() }
            window.onSpace = { [weak self] in self?.close() }
            window.onJump = { [weak self] in self?.state.isJumping = true }
            window.center()
            self.window = window
            self.sceneController = sceneController
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        sceneController?.installScrollZoomMonitor()
    }

    /// Esc walks back inside the Globe before it ever closes the window.
    private func performEscapeStep() {
        switch state.escapeStep {
        case .cancelJump:
            state.cancelJump()
        case .closeInspection:
            state.inspection = nil
        case .closeGlobe:
            close()
        }
    }

    func close() {
        sceneController?.removeScrollZoomMonitor()
        window?.close()
        onClose?()
    }
}
