import AppKit
import SwiftUI

/// List on macOS ignores `.scrollIndicators(.hidden)` — its backing
/// NSScrollView keeps its overlay scroller. Placed as a row background, this
/// reaches that scroll view and removes the scrollers directly.
struct HiddenListScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            Self.hideScrollers(enclosing: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            Self.hideScrollers(enclosing: nsView)
        }
    }

    @MainActor
    private static func hideScrollers(enclosing view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
    }
}
