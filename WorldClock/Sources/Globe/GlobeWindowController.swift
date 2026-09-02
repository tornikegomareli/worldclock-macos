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

    /// Where the Globe expanded from — the close animation returns there:
    /// objects remember where they came from.
    private var originFrame: NSRect?

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

    func toggle(from panelFrame: NSRect? = nil) {
        if isVisible {
            close()
        } else {
            open(from: panelFrame)
        }
    }

    func open(from panelFrame: NSRect? = nil) {
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
        originFrame = panelFrame
        present()
        sceneController?.installScrollZoomMonitor()
    }

    /// The spatial half of the Panel↔Globe transition: the window expands
    /// out of the Panel's frame and later shrinks back into it. Under the
    /// crossfade policy it fades in place instead.
    private func present() {
        guard let window else { return }
        let target = targetFrame(near: originFrame)
        if settings.prefersCrossfade || originFrame == nil {
            window.setFrame(target, display: false)
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = settings.animationsEnabled ? 0.2 : 0
                window.animator().alphaValue = 1
            }
        } else {
            window.setFrame(originFrame ?? target, display: false)
            window.alphaValue = 0.3
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = 1
            }
        }
    }

    private func targetFrame(near origin: NSRect?) -> NSRect {
        let screen = origin.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: 760, height: 680)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
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
        guard let window, window.isVisible else {
            onClose?()
            return
        }
        let finish: () -> Void = { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1
            self?.onClose?()
        }
        if settings.prefersCrossfade || originFrame == nil {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = settings.animationsEnabled ? 0.15 : 0
                window.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(originFrame ?? window.frame, display: true)
                window.animator().alphaValue = 0
            }, completionHandler: finish)
        }
    }
}
