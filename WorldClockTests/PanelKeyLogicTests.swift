import Foundation
import Testing
@testable import WorldClock

/// Keyboard policy for the Panel: selection stepping and the Esc walk-back
/// order. Pure functions — the key routing itself is shell.
@Suite("PanelKeyLogic")
struct PanelKeyLogicTests {
    let locations = [
        Location(cityName: "Tbilisi", timeZone: TimeZone(identifier: "Asia/Tbilisi")!),
        Location(cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!),
        Location(cityName: "Tokyo", timeZone: TimeZone(identifier: "Asia/Tokyo")!),
    ]

    @Test("Arrow keys enter the list from either end and step through it")
    func selectionStepping() {
        // No selection: ↓ selects the first Location, ↑ the last.
        #expect(PanelKeyLogic.movedSelection(from: nil, by: .down, in: locations) == "Asia/Tbilisi")
        #expect(PanelKeyLogic.movedSelection(from: nil, by: .up, in: locations) == "Asia/Tokyo")

        // Stepping moves one Location at a time.
        #expect(PanelKeyLogic.movedSelection(from: "Asia/Tbilisi", by: .down, in: locations) == "Europe/London")
        #expect(PanelKeyLogic.movedSelection(from: "Europe/London", by: .up, in: locations) == "Asia/Tbilisi")
    }

    @Test("Selection clamps at the ends instead of wrapping")
    func selectionClamps() {
        #expect(PanelKeyLogic.movedSelection(from: "Asia/Tokyo", by: .down, in: locations) == "Asia/Tokyo")
        #expect(PanelKeyLogic.movedSelection(from: "Asia/Tbilisi", by: .up, in: locations) == "Asia/Tbilisi")
    }

    @Test("An empty list yields no selection")
    func emptyList() {
        #expect(PanelKeyLogic.movedSelection(from: nil, by: .down, in: []) == nil)
    }

    @Test("After Delete, selection moves to the neighbour instead of vanishing")
    func selectionAfterRemoval() {
        // Removing London (middle): the Location that takes its index — Tokyo.
        #expect(
            PanelKeyLogic.selectionAfterRemoval(of: "Europe/London", from: locations) == "Asia/Tokyo"
        )
        // Removing the last Location clamps back to the new last.
        #expect(
            PanelKeyLogic.selectionAfterRemoval(of: "Asia/Tokyo", from: locations) == "Europe/London"
        )
        // Removing an id not in the list leaves no selection.
        #expect(PanelKeyLogic.selectionAfterRemoval(of: "Mars/Olympus", from: locations) == nil)
    }

    @Test("Esc walks back one layer at a time: search, inspection, Time Travel, selection, close")
    func escapeWalkBack() {
        let simulated = TimeState.simulated(Date(timeIntervalSince1970: 0))

        // Search always cancels first, whatever else is active.
        #expect(
            PanelKeyLogic.escapeStep(isSearching: true, isInspecting: true, timeState: simulated, hasSelection: true)
                == .cancelSearch
        )
        // Then an open inspection closes.
        #expect(
            PanelKeyLogic.escapeStep(isSearching: false, isInspecting: true, timeState: simulated, hasSelection: true)
                == .closeInspection
        )
        // Then Time Travel returns to Now (CONTEXT.md).
        #expect(
            PanelKeyLogic.escapeStep(isSearching: false, isInspecting: false, timeState: simulated, hasSelection: true)
                == .returnToNow
        )
        // Then a selection clears.
        #expect(
            PanelKeyLogic.escapeStep(isSearching: false, isInspecting: false, timeState: .now, hasSelection: true)
                == .clearSelection
        )
        // With nothing left, the Panel closes.
        #expect(
            PanelKeyLogic.escapeStep(isSearching: false, isInspecting: false, timeState: .now, hasSelection: false)
                == .closePanel
        )
    }
}
