import Foundation

/// Where a transient overlay's page stands relative to the request behind it.
///
/// The cases are the ladder both shells walk, in order. An overlay that is no
/// longer the presented one answers for nothing. A request whose Space has
/// gone answers for nothing more. A locked Space keeps its pages off screen.
/// Only the last rung may hold a live page, and it carries the Space that page
/// belongs to.
///
/// What each shell *does* about a rung is its own business, and differs even
/// between two calls on one shell: a macOS Peek that loses its Space while
/// preparing tears the request down, while the same loss noticed as the window
/// resigns key only lets the page go. So the ladder is shared as a reading
/// rather than as an action.
enum BrowserTransientLeaseDisposition: Equatable, Sendable {
    case notPresented
    case sourceMissing
    case sourceLocked
    case usable(BrowserSpace)
}

/// The two Spaces a promotion has to line up before a transient page can
/// become a real tab.
struct BrowserTransientPromotionSpaces: Equatable, Sendable {
    let source: BrowserSpace
    let destination: BrowserSpace
}

/// The decisions every transient overlay's model makes about its page.
///
/// Both shells run these over different lease, page, and store types, so the
/// reasoning lives here and each shell performs the outcome against its own
/// types.
enum BrowserTransientSessionPolicy {
    @MainActor
    static func disposition(
        isPresentingRequest: Bool,
        space: BrowserSpace?,
        isLocked: @MainActor (BrowserSpace) -> Bool
    ) -> BrowserTransientLeaseDisposition {
        guard isPresentingRequest else { return .notPresented }
        guard let space else { return .sourceMissing }
        guard !isLocked(space) else { return .sourceLocked }
        return .usable(space)
    }

    /// The Spaces a transient overlay may be promoted into.
    ///
    /// A Space being torn down is never a destination. Nor is a locked one —
    /// except the request's own Space, which stays listed so the overlay can
    /// keep naming where it came from even while that Space locks behind it.
    @MainActor
    static func availableSpaces(
        in spaces: [BrowserSpace],
        deletingSpaceIDs: Set<SpaceID>,
        requestSpaceID: SpaceID,
        isLocked: @MainActor (BrowserSpace) -> Bool
    ) -> [BrowserSpace] {
        spaces.filter {
            !deletingSpaceIDs.contains($0.id)
                && ($0.id == requestSpaceID || !isLocked($0))
        }
    }

    /// Whether the lease already in hand still serves this request, rather
    /// than being a leftover from a Space the request no longer names, or a
    /// page that has been let go for good.
    static func reusesLease(
        leaseAssignment: BrowserSpaceRuntimeAssignment,
        requestAssignment: BrowserSpaceRuntimeAssignment,
        leaseCanBeReused: Bool
    ) -> Bool {
        leaseAssignment == requestAssignment && leaseCanBeReused
    }

    /// The Spaces a promotion may run between, or `nil` where either end has
    /// gone or locked.
    @MainActor
    static func promotionSpaces(
        source: BrowserSpace?,
        destination: BrowserSpace?,
        isLocked: @MainActor (BrowserSpace) -> Bool
    ) -> BrowserTransientPromotionSpaces? {
        guard let source,
            !isLocked(source),
            let destination,
            !isLocked(destination)
        else { return nil }
        return BrowserTransientPromotionSpaces(
            source: source,
            destination: destination
        )
    }

    /// Whether the live web view may move into the new tab as it stands.
    ///
    /// It may only when the lease is already held by the Space the tab was
    /// opened in; anything else would hand a page to a Space that never owned
    /// it, so the destination loads the URL fresh instead.
    static func adoptsLivePage(
        leaseAssignment: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpace
    ) -> Bool {
        leaseAssignment == BrowserSpaceRuntimeAssignment(space: destination)
    }
}
