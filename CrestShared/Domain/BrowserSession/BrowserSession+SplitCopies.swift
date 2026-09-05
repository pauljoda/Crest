import Foundation

extension BrowserSession {
    /// Prepares the entire join in a value copy. A refused intent publishes no
    /// tabs, selection changes, or partially copied groups.
    mutating func addTabToSplitPreservingDurableTabs(
        _ tabID: TabID,
        joining targetTabID: TabID,
        at memberIndex: Int?,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> [(source: TabID, copy: TabID)]? {
        guard spaceID == selectedSpaceID, tabID != targetTabID,
            let space = space(id: spaceID),
            let source = space.tabs.first(where: { $0.id == tabID }),
            let target = space.tabs.first(where: { $0.id == targetTabID }),
            !source.isStartPage, !target.isStartPage
        else { return nil }
        let members = target.splitGroupID.map { space.splitGroupMembers(of: $0) } ?? [target]
        if members.contains(where: { $0.id == source.id }) {
            guard memberIndex != nil,
                addTabToSplit(tabID, joining: targetTabID, at: memberIndex, in: spaceID, at: date)
            else { return nil }
            return []
        }
        guard members.count < BrowserSplitGroupPolicy.maximumMembers else { return nil }

        var draft = self
        var copies: [(source: TabID, copy: TabID)] = []
        var destinationID = targetTabID
        if target.placement != .current {
            var destinationMembers: [TabID] = []
            let insertionIndex = space.tabs.firstIndex { $0.placement == .current } ?? space.tabs.endIndex
            for member in members {
                guard
                    let copyID = draft.duplicateTab(
                        member.id, in: spaceID, requestedIndex: insertionIndex + destinationMembers.count,
                        shouldSelect: false, at: date
                    )
                else { return nil }
                copies.append((member.id, copyID))
                destinationMembers.append(copyID)
                if member.id == targetTabID { destinationID = copyID }
            }
            guard let headID = destinationMembers.first else { return nil }
            for memberID in destinationMembers.dropFirst() {
                guard draft.addTabToSplit(memberID, joining: headID, at: nil, in: spaceID, at: date)
                else { return nil }
            }
        }
        var joinerID = tabID
        if source.placement != .current {
            guard let copyID = draft.duplicateTab(tabID, in: spaceID, shouldSelect: false, at: date)
            else { return nil }
            copies.append((tabID, copyID))
            joinerID = copyID
        }
        guard draft.addTabToSplit(joinerID, joining: destinationID, at: memberIndex, in: spaceID, at: date)
        else { return nil }
        if target.placement != .current,
            let oldGroupID = target.splitGroupID,
            let metadata = space.splitGroupMetadata(for: oldGroupID),
            let spaceIndex = draft.spaces.firstIndex(where: { $0.id == spaceID }),
            let groupID = draft.spaces[spaceIndex].splitGroup(containing: destinationID)
        {
            draft.spaces[spaceIndex].splitGroups.removeAll { $0.id == groupID }
            draft.spaces[spaceIndex].splitGroups.append(
                BrowserSplitGroupMetadata(
                    id: groupID, customTitle: metadata.customTitle, titleModifiedAt: date,
                    customIconSymbol: metadata.customIconSymbol, iconModifiedAt: date,
                    tint: metadata.tint, tintModifiedAt: date
                )
            )
        }
        self = draft
        return copies
    }
}
