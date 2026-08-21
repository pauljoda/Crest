import Foundation

/// The decision a content area makes before it draws anything: columns or the
/// single page surface, and for which Space.
///
/// Written once because both shells were writing it, and a disagreement is not
/// cosmetic — the two layouts host the live web view in different places, so a
/// shell that opens columns one condition earlier than the other rebuilds a
/// page's host where the other does not.
///
/// Membership is asked of `presentedSplitMembers(for:)` and never of
/// `BrowserTab.splitGroupID`: a run too short to render still keeps its stored
/// group ID so a staggered sync can reconstitute the group, and only that
/// accessor knows the difference between the two.
enum BrowserPageSurfaceBranchPolicy {
    /// - Parameters:
    ///   - hasEnteredSplitContent: Whether a drag has already reached the
    ///     content area during this lift. It holds the columns layout open
    ///     around a single presented tab for the rest of the drag rather than
    ///     following the pointer back and forth, because every flip between the
    ///     two layouts hands the live web view to a different host, while the
    ///     placeholder coming and going inside the columns layout is only a
    ///     width change.
    ///   - resolvedTarget: Where the lift in flight would land. Only a
    ///     `.splitInsert` aimed at this very Space opens a slot in this row.
    static func resolve(
        selectedSpace: BrowserSpace?,
        isSelectedSpaceLocked: Bool,
        selectedTabID: TabID?,
        hasEnteredSplitContent: Bool,
        resolvedTarget: BrowserSidebarReorderTarget?
    ) -> BrowserPageSurfacePresentation {
        guard let space = selectedSpace, !isSelectedSpaceLocked else {
            return .unavailable
        }

        let members = space.presentedSplitMembers(for: selectedTabID)
        guard !members.isEmpty, members.count > 1 || hasEnteredSplitContent
        else {
            return .single(space: space, cardTabID: selectedTabID)
        }

        return .columns(
            space: space,
            members: members,
            placeholderIndex: placeholderIndex(
                resolvedTarget: resolvedTarget,
                spaceID: space.id
            )
        )
    }

    /// The slot a drag in flight would drop a card into, for this Space.
    private static func placeholderIndex(
        resolvedTarget: BrowserSidebarReorderTarget?,
        spaceID: SpaceID
    ) -> Int? {
        guard
            case .splitInsert(let assignment, let index) = resolvedTarget?.kind,
            assignment.spaceID == spaceID
        else { return nil }
        return index
    }
}
