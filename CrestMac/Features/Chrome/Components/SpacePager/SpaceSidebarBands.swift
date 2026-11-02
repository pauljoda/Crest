import SwiftUI

extension EnvironmentValues {
    @Entry var spaceSidebarBands: SpaceSidebarBands?
}

/// Where each Space's sidebar page ends its extension strip and its pinned
/// tabs, as the pages lay out. The Spaces of one group show the same strip,
/// and the same pinned tabs while the group shares them, so the pager holds
/// that band still while it slides between them, and asks for it as a slide
/// begins.
@MainActor
final class SpaceSidebarBands {
    // MARK: - Static Variables

    /// The coordinate space of a Space's sidebar page, from the top of the
    /// view the pager hosts it in.
    static let page = "space-sidebar-page"

    // MARK: - Variables

    /// Each Space's pinned tabs in its page, from the bottom of the strip
    /// above them to their own bottom.
    private var pins: [UUID: ClosedRange<CGFloat>] = [:]

    // MARK: - Actions - Bands

    /// How much of the top of their pages `first` and `second` show alike:
    /// the strip and the pinned tabs while they share pins, the strip alone
    /// while they share only a session, and nothing otherwise or when that
    /// band holds nothing above the room a selected pin's glow takes.
    func sharedHeight(between first: SpaceModel, and second: SpaceModel) -> CGFloat {
        guard first.profileID == second.profileID, let firstPins = pins[first.id], let secondPins = pins[second.id]
        else { return 0 }
        let height =
            first.pinSource.id == second.pinSource.id && abs(firstPins.upperBound - secondPins.upperBound) < 0.5
            ? firstPins.upperBound
            : abs(firstPins.lowerBound - secondPins.lowerBound) < 0.5 ? firstPins.lowerBound : 0
        return height > BrowserTabSelectionGlow.outset + 0.5 ? height : 0
    }

    // MARK: - Mutators

    /// Records where `spaceID`'s pinned tabs lie in its page, `frame`.
    func record(_ frame: CGRect, for spaceID: UUID) {
        pins[spaceID] = frame.minY...frame.maxY
    }

    /// Forgets `spaceID`'s pinned tabs, which its page no longer shows.
    func forget(_ spaceID: UUID) {
        pins[spaceID] = nil
    }
}
