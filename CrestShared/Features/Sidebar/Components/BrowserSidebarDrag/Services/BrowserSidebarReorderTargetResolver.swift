import CoreGraphics

/// Resolves a pointer against one lift's projected rows and visible drop zones.
@MainActor
struct BrowserSidebarReorderTargetResolver {
    let lift: BrowserSidebarReorderState.Lift
    let pointer: CGPoint
    let insertionPoint: CGPoint
    let layout: BrowserSidebarReorderLayout
    let pinned: (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)?
    let zones: [BrowserSidebarReorderZone]
    let rows: [BrowserSidebarReorderItemID: BrowserSidebarReorderGeometry.RegisteredRow]
    let splitCards: [TabID: BrowserSidebarReorderGeometry.SplitCard]

    func resolve(previousTarget: BrowserSidebarReorderTarget?) -> BrowserSidebarReorderTarget? {
        // Keep the open gap stable while neighbouring rows animate around it.
        if let gap = layout.gapFrame, gap.contains(insertionPoint) { return previousTarget }
        if let pinned, let gap = pinned.layout.frame(for: .gap, in: pinned.frame), gap.contains(pointer) {
            return previousTarget
        }
        let available = zones.filter { !$0.frame.isEmpty && allowsNesting(in: $0) }
        let direct = BrowserSidebarReorderPolicy.zone(at: pointer, in: available, accepting: lift.item)
        let nesting: BrowserSidebarReorderZone? =
            switch direct?.target {
            case .folder, .currentFolder, .currentTab: direct
            default: nil
            }
        guard
            let zone = nesting
                ?? BrowserSidebarReorderPolicy.zone(
                    at: insertionPoint, in: available, accepting: lift.item)
        else { return nil }

        switch zone.target {
        case .currentTab(let tabID):
            return BrowserSidebarReorderTarget(kind: .createCurrentFolder(tabID))
        case .space(let assignment):
            return BrowserSidebarReorderTarget(kind: .space(assignment))
        case .folder(let folderID), .currentFolder(let folderID):
            return lift.item.id == .folder(folderID)
                ? nil : BrowserSidebarReorderTarget(kind: .intoFolder(folderID))
        case .section(let section):
            return insertionTarget(in: section)
        case .splitContent(let assignment):
            return splitInsertTarget(in: assignment)
        }
    }

    private func insertionTarget(in section: BrowserSidebarReorderSection)
        -> BrowserSidebarReorderTarget?
    {
        if section == lift.section, let parentID = rows[lift.item.id]?.row.parentItemID,
            let parent = rows[parentID]?.row, layout.frame(for: parent)?.contains(pointer) == true
        {
            return nil
        }
        let ordered = BrowserSidebarReorderPolicy.rows(
            in: section,
            from: rows.values.map(\.row).filter { $0.space == lift.item.spaceAssignment && $0.parentItemID == nil }
                .compactMap {
                    row in
                    let frame: CGRect?
                    if row.usesGridOrdering, let pinned {
                        frame = pinned.layout.frame(for: .tab(row.id), in: pinned.frame)
                    } else {
                        frame = layout.frame(for: row)
                    }
                    guard let frame else { return nil }
                    return BrowserSidebarReorderRow(
                        id: row.id, space: row.space, section: row.section, frame: frame)
                })
        let candidates = ordered.filter { !lift.item.selectionRowIDs.contains($0.id) }
        guard
            lift.item.selection != nil
                || BrowserSidebarReorderPolicy.hasRoom(
                    for: lift.item, in: section, existingCount: candidates.count,
                    isAlreadyInSection: lift.section == section)
        else { return nil }
        let index = BrowserSidebarReorderPolicy.insertionIndex(
            at: insertionPoint, orderedRows: candidates, excluding: lift.item.id)
        let anchor = BrowserSidebarReorderPolicy.insertionAnchor(
            index: index, orderedRows: candidates, excluding: lift.item.id)
        return BrowserSidebarReorderTarget(
            kind: .insert(section: section, beforeID: anchor, index: index))
    }

    /// Horizontal movement admits deeper folder sections; vertical motion stays among siblings.
    private func allowsNesting(in zone: BrowserSidebarReorderZone) -> Bool {
        guard case .folder = lift.item, case .section(let section) = zone.target else { return true }
        let startX = layout.sourceFrame.minX + lift.grabOffset.width
        let extraDepth = max(0, Int((pointer.x - startX) / BrowserFolderLayout.nestingIndent))
        return folderDepth(of: section) <= folderDepth(of: lift.section) + extraDepth
    }

    private func folderDepth(of section: BrowserSidebarReorderSection) -> Int {
        var ancestors: Set<FolderID> = []
        var parent = section.parentFolderID
        while let id = parent, ancestors.insert(id).inserted {
            parent = rows[.folder(id)]?.row.section.parentFolderID
        }
        return ancestors.count
    }

    private func splitInsertTarget(in assignment: BrowserSpaceRuntimeAssignment)
        -> BrowserSidebarReorderTarget?
    {
        // Departing Space cards may remain registered until their transition finishes.
        let cards = splitCards.filter { $0.value.space == assignment && !$0.value.frame.isEmpty }
        guard !cards.isEmpty else { return nil }
        if lift.item.selection == nil {
            guard case .tab(let item) = lift.item,
                cards[item.tabID] == nil, cards.count < BrowserSplitGroupPolicy.maximumMembers
            else { return nil }
        }
        return BrowserSidebarReorderTarget(
            kind: .splitInsert(
                assignment: assignment,
                index: BrowserSplitDropPolicy.insertionIndex(
                    at: pointer, orderedCardFrames: BrowserSplitDropPolicy.ordered(cards.values.map(\.frame)))
            ))
    }
}
