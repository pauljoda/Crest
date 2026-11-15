import SwiftUI

/// Where the address fields the window's command palette drops out of lie in
/// the window: the window's own field along the top of a lone page, and the
/// field of each card of a split, by the tab the card shows.
///
/// The cards live in the Space pager's own hosting views, which no preference
/// crosses, so each field reports its frame here in the window's coordinates
/// and the palette converts it to its own.
@MainActor @Observable
final class BrowserPageBarFieldFrames {
    // MARK: - Variables

    private var frames: [UUID: CGRect] = [:]

    /// The window's own address field along the top of a lone page, while
    /// it shows there.
    private(set) var windowFrame: CGRect?

    // MARK: - Actions - Frames

    /// The field of the card showing `tabID`, in window coordinates.
    func frame(for tabID: UUID) -> CGRect? {
        frames[tabID]
    }

    /// Records where the field of the card showing `tabID` lies.
    func register(_ frame: CGRect, for tabID: UUID) {
        guard frames[tabID] != frame else { return }
        frames[tabID] = frame
    }

    /// Forgets the field of a card that left the window.
    func removeFrame(for tabID: UUID) {
        frames[tabID] = nil
    }

    /// Records where the window's own field lies, or forgets it once the
    /// field leaves the top of the page.
    func registerWindowFrame(_ frame: CGRect?) {
        guard windowFrame != frame else { return }
        windowFrame = frame
    }
}
