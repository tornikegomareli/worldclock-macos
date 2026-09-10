import Foundation

/// Pure keyboard policy for the Panel — selection stepping and the Esc
/// walk-back order. The event routing that invokes it lives in the shell.
enum PanelKeyLogic {
    static func movedResultSelection(from current: Int, by delta: Int, count: Int) -> Int {
        min(max(current + delta, 0), max(count - 1, 0))
    }

    enum SelectionDirection {
        case up
        case down
    }

    /// Keyboard-first Delete: the selection moves to the Location that takes
    /// the removed one's place (clamped to the new end) instead of vanishing.
    /// `locations` is the list before removal.
    static func selectionAfterRemoval(of removed: Location.ID, from locations: [Location]) -> Location.ID? {
        guard let index = locations.firstIndex(where: { $0.id == removed }) else { return nil }
        let remaining = locations.filter { $0.id != removed }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)].id
    }

    enum EscapeStep: Equatable {
        case cancelSearch
        case closeInspection
        case returnToNow
        case clearSelection
        case closePanel
    }

    /// Esc walks back one layer at a time: an open search cancels first,
    /// then inspection closes, then Time Travel returns to Now (CONTEXT.md),
    /// then the selection clears; only from a bare Now Panel does Esc close it.
    static func escapeStep(
        isSearching: Bool,
        isInspecting: Bool,
        timeState: TimeState,
        hasSelection: Bool
    ) -> EscapeStep {
        if isSearching { return .cancelSearch }
        if isInspecting { return .closeInspection }
        if timeState != .now { return .returnToNow }
        if hasSelection { return .clearSelection }
        return .closePanel
    }

    /// The Location selected after an arrow key: enters the list from the
    /// top (↓) or bottom (↑) when nothing is selected, otherwise steps one
    /// Location, clamping at the ends.
    static func movedSelection(
        from current: Location.ID?,
        by direction: SelectionDirection,
        in locations: [Location]
    ) -> Location.ID? {
        guard !locations.isEmpty else { return nil }
        guard let current, let index = locations.firstIndex(where: { $0.id == current }) else {
            return direction == .down ? locations.first?.id : locations.last?.id
        }
        let stepped = direction == .down ? index + 1 : index - 1
        let clamped = min(max(stepped, 0), locations.count - 1)
        return locations[clamped].id
    }
}
