/// Where a lifted sidebar item will land when released.
struct BrowserSidebarReorderTarget: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Insert into an ordered section before `beforeID` (`nil` appends).
        /// `index` is the resolved slot, used to displace neighbours.
        case insert(
            section: BrowserSidebarReorderSection,
            beforeID: BrowserSidebarReorderItemID?,
            index: Int
        )
        /// Land inside a collapsed folder.
        case intoFolder(FolderID)
        /// Move to another space.
        case space(BrowserSpaceRuntimeAssignment)
        /// Join the cards the content area is presenting, as the card at
        /// `index` among them. The index counts presented cards only — the drop
        /// placeholder is not one of them — so it stays put as the row of cards
        /// shifts to make room.
        case splitInsert(assignment: BrowserSpaceRuntimeAssignment, index: Int)
    }

    let kind: Kind

    var section: BrowserSidebarReorderSection? {
        guard case let .insert(section, _, _) = kind else { return nil }
        return section
    }
}
