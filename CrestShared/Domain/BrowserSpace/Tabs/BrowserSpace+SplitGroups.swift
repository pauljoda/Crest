import Foundation

/// TRANSITIONAL until S6.6d moves the window's root and commands onto the
/// read model: the splits of a Space of the session copy, as the content area
/// and the commands still read them. The sidebar reads the core's outline.
extension BrowserSpace {
    /// The renderable split group this tab belongs to, or `nil`.
    ///
    /// A run shorter than `SplitGroupState.minimumShownMembers` answers `nil`
    /// on purpose: storage keeps a lone member's ID so a
    /// staggered sync can reconstitute the group, while every presentation
    /// surface treats that member as a plain tab until its siblings arrive.
    func splitGroup(containing tabID: TabID) -> SplitGroupID? {
        guard let groupID = tabs.first(where: { $0.id == tabID })?.splitGroupID else {
            return nil
        }
        let members = splitGroupMembers(of: groupID)
        guard members.count >= SplitGroupState.minimumShownMembers,
            members.contains(where: { $0.id == tabID })
        else { return nil }
        return groupID
    }

    /// The group's members in session-array order: the first maximal
    /// contiguous run of tabs carrying `groupID`.
    func splitGroupMembers(of groupID: SplitGroupID) -> [BrowserTab] {
        guard let start = tabs.firstIndex(where: { $0.splitGroupID == groupID }) else {
            return []
        }
        var end = start
        while end < tabs.endIndex, tabs[end].splitGroupID == groupID {
            end += 1
        }
        return Array(tabs[start..<end])
    }

    /// The cards the content area presents for this selection: the selected
    /// tab's renderable run, otherwise just the selected tab, otherwise
    /// nothing. The single-tab case is deliberately the same shape as a group
    /// so no surface has to special-case it.
    func presentedSplitMembers(for selectedTabID: TabID?) -> [BrowserTab] {
        guard let selectedTabID,
            let selectedTab = tabs.first(where: { $0.id == selectedTabID })
        else { return [] }
        guard let groupID = splitGroup(containing: selectedTabID) else {
            return [selectedTab]
        }
        return splitGroupMembers(of: groupID)
    }
}
