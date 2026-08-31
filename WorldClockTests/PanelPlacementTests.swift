import CoreGraphics
import Testing
@testable import WorldClock

@Suite("PanelPlacement")
struct PanelPlacementTests {
    let panelSize = CGSize(width: 320, height: 360)
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let gap: CGFloat = 4

    @Test("Panel is centered under the status item, just below the menu bar")
    func centeredUnderStatusItem() {
        let statusItemFrame = CGRect(x: 700, y: 950, width: 30, height: 24)

        let frame = PanelPlacement.frame(
            anchoredUnder: statusItemFrame,
            panelSize: panelSize,
            screenFrame: screenFrame,
            gap: gap
        )

        #expect(frame.midX == statusItemFrame.midX)
        #expect(frame.maxY == statusItemFrame.minY - gap)
        #expect(frame.size == panelSize)
    }

    @Test("Panel clamps to the right screen edge for a status item near the corner")
    func clampsToRightEdge() {
        let statusItemFrame = CGRect(x: 1480, y: 950, width: 30, height: 24)

        let frame = PanelPlacement.frame(
            anchoredUnder: statusItemFrame,
            panelSize: panelSize,
            screenFrame: screenFrame,
            gap: gap
        )

        #expect(frame.maxX == screenFrame.maxX)
        #expect(frame.maxY == statusItemFrame.minY - gap)
    }

    @Test("Panel clamps to the left screen edge")
    func clampsToLeftEdge() {
        let statusItemFrame = CGRect(x: 10, y: 950, width: 30, height: 24)

        let frame = PanelPlacement.frame(
            anchoredUnder: statusItemFrame,
            panelSize: panelSize,
            screenFrame: screenFrame,
            gap: gap
        )

        #expect(frame.minX == screenFrame.minX)
    }
}
