import CoreGraphics

/// Pure geometry for anchoring the Panel under the menu-bar status item.
/// All rects use AppKit screen coordinates (origin bottom-left, y grows upward).
enum PanelPlacement {
    static func frame(
        anchoredUnder statusItemFrame: CGRect,
        panelSize: CGSize,
        screenFrame: CGRect,
        gap: CGFloat = 4
    ) -> CGRect {
        var x = statusItemFrame.midX - panelSize.width / 2
        x = min(max(x, screenFrame.minX), screenFrame.maxX - panelSize.width)
        let y = statusItemFrame.minY - gap - panelSize.height
        return CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }
}
