import AppKit
import Testing
@testable import WorldClock

@Suite("Panel text editing")
@MainActor
struct FloatingPanelTests {
    @Test("Command-A selects the search text without invoking panel shortcuts")
    func selectAll() throws {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                  styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let editor = NSTextView(frame: panel.contentView!.bounds)
        editor.string = "San Francisco"
        panel.contentView = editor
        #expect(panel.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        var routedToPanel = false
        panel.onKeyEvent = { _ in routedToPanel = true; return true }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        panel.sendEvent(event)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 13))
        #expect(editor.string == "San Francisco")
        #expect(!routedToPanel)
    }
}
