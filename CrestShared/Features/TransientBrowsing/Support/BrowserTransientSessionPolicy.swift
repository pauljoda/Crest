import Foundation

/// Describes whether a transient request may retain a live page.
enum BrowserTransientLeaseDisposition: Equatable, Sendable {
    case notPresented
    case sourceMissing
    case sourceLocked
    case usable(BrowserSpace)
}

/// The authorized source and destination of a transient promotion.
struct BrowserTransientPromotionSpaces: Equatable, Sendable {
    let source: BrowserSpace
    let destination: BrowserSpace
}

/// Shared ownership and authorization rules for transient pages.
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

    /// Excludes deleting and locked destinations, retaining the named source Space.
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

    /// A reusable lease must still match the request’s runtime assignment.
    static func reusesLease(
        leaseAssignment: BrowserSpaceRuntimeAssignment,
        requestAssignment: BrowserSpaceRuntimeAssignment,
        leaseCanBeReused: Bool
    ) -> Bool {
        leaseAssignment == requestAssignment && leaseCanBeReused
    }

    /// Both Spaces must exist and remain unlocked before promotion.
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

    /// A page can be adopted only by the Space and profile that already own it.
    static func adoptsLivePage(
        leaseAssignment: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpace
    ) -> Bool {
        leaseAssignment == BrowserSpaceRuntimeAssignment(space: destination)
    }
}
