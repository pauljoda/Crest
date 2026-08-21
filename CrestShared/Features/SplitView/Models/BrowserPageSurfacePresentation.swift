import Foundation

/// What a content area is presenting: a row of cards, or the one page surface.
///
/// Resolved by `BrowserPageSurfaceBranchPolicy` and then only drawn, so a shell
/// reads the branch rather than deciding it.
enum BrowserPageSurfacePresentation: Equatable, Sendable {
    /// The single surface with no Space of its own behind it — none is
    /// selected, or the selected one is locked and showing its access gate
    /// instead of pages. Nothing may be dropped into it: the page store has
    /// already let every card go, and a Space that has not been unlocked is not
    /// somewhere a tab may land.
    case unavailable

    /// The single rounded surface, presenting `space`. `cardTabID` is the lone
    /// tab a drag can drop beside — what a dropped tab would join, and the side
    /// of it the pointer is on is which side the new card lands.
    case single(space: BrowserSpace, cardTabID: TabID?)

    /// A row of cards. `placeholderIndex` is the slot a drag in flight would
    /// drop into, or `nil` when no drop is resolved against this row.
    case columns(
        space: BrowserSpace,
        members: [BrowserTab],
        placeholderIndex: Int?
    )

    /// The Space whose cards this window is showing, or `nil` when there are
    /// none to show.
    var presentingSpace: BrowserSpace? {
        switch self {
        case .unavailable: nil
        case .single(let space, _): space
        case .columns(let space, _, _): space
        }
    }

    /// The Space a drag over the content area resolves against — the presented
    /// one, so a card lands in the Space it was dropped on rather than the one
    /// whose sidebar the drag started in.
    var dropAssignment: BrowserSpaceRuntimeAssignment? {
        presentingSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    /// The tab the single surface is showing, when there is one to drop beside.
    var singleCardTabID: TabID? {
        guard case .single(_, let cardTabID) = self else { return nil }
        return cardTabID
    }
}
