import SwiftUI

/// Where the address fields the window's command palette drops out of lie in
/// the window: the window's own field along the top of a lone page, and the
/// field of each card of a split, by the tab the card shows.
///
/// The cards live in the Space pager's own hosting views, which no preference
/// crosses, so each field reports its frame here in the window's coordinates
/// and the palette converts it to its own.
///
/// A card's entry is stamped with the field that made it. One field for a tab
/// can arrive before another for the same tab has gone, as a card leaves mid
/// transition or a tab shows in two Spaces of a group during a swipe, and the
/// departing field's exit must not clear the entry the arriving one made.
@MainActor @Observable
final class BrowserPageBarFieldFrames {
    // MARK: - Types

    private struct Entry: Equatable {
        let frame: CGRect
        /// The field that registered it.
        let owner: UUID
    }

    // MARK: - Variables

    private var frames: [UUID: Entry] = [:]

    /// The window's own address field along the top of a lone page, while
    /// it shows there.
    private(set) var windowFrame: CGRect?

    // MARK: - Actions - Frames

    /// The field of the card showing `tabID`, in window coordinates.
    func frame(for tabID: UUID) -> CGRect? {
        frames[tabID]?.frame
    }

    /// Records where `owner`, the field of the card showing `tabID`, lies.
    func register(_ frame: CGRect, for tabID: UUID, owner: UUID) {
        let entry = Entry(frame: frame, owner: owner)
        guard frames[tabID] != entry else { return }
        frames[tabID] = entry
    }

    /// Forgets the field of a card that left the window, unless another
    /// field for the same tab has registered since.
    func removeFrame(for tabID: UUID, owner: UUID) {
        guard frames[tabID]?.owner == owner else { return }
        frames[tabID] = nil
    }

    /// Records where the window's own field lies, or forgets it once the
    /// field leaves the top of the page.
    func registerWindowFrame(_ frame: CGRect?) {
        guard windowFrame != frame else { return }
        windowFrame = frame
    }
}
