import SwiftUI

/// Whether a Space swipe has a Space showing a split in view, whose cards
/// carry bars of their own that the window's address bar would cover.
///
/// It follows the pager's snapshots the way the pager's other leaves do,
/// without observing the pager, and changes only as a split comes into view or
/// leaves it, so a swipe redraws nothing frame by frame.
@MainActor @Observable
final class BrowserWindowBarSwipeWatch {
    // MARK: - Variables

    private(set) var showsSplitInView = false
    @ObservationIgnored private var presentation: SpacePagerPresentation?
    /// Whether the window shows a split in the Space with this identifier.
    @ObservationIgnored private var presentsSplit: (UUID) -> Bool = { _ in false }

    // MARK: - Actions - Presentation

    func connect(_ presentation: SpacePagerPresentation?, presentsSplit: @escaping (UUID) -> Bool) {
        if self.presentation !== presentation { disconnect() }
        self.presentation = presentation
        self.presentsSplit = presentsSplit
        presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        show(false)
    }

    /// Looks at the two Spaces a snapshot has in view while it moves; at rest
    /// the window shows one Space, whose own bar decides.
    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.phase != .idle,
            let sample = SpacePagerInterpolation(position: snapshot.position, count: snapshot.spaceIDs.count)
        else { return show(false) }
        show(presentsSplit(snapshot.spaceIDs[sample.lower]) || presentsSplit(snapshot.spaceIDs[sample.upper]))
    }

    private func show(_ showsSplit: Bool) {
        if showsSplitInView != showsSplit { showsSplitInView = showsSplit }
    }
}
