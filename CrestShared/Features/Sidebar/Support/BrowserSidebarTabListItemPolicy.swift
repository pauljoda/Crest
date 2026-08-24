import Foundation

/// Folds a section's tabs into the rows the sidebar draws.
///
/// The rules mirror the domain exactly, because presentation and storage must
/// agree on what a group is: a group is the *first* maximal contiguous run of
/// tabs sharing a `splitGroupID`, and a run shorter than
/// `BrowserSplitGroupPolicy.minimumRenderableMembers` is not a group at all —
/// storage keeps a lone member's ID so a staggered sync can reconstitute the
/// split, while the sidebar shows it as an ordinary tab until its siblings
/// arrive.
///
/// Input is normally post-normalizer, where runs are already well formed. The
/// defensive arms below (pinned members, a repeated group ID, a run of one) cost
/// nothing and keep a half-materialized session from rendering two rows that
/// claim the same identity.
enum BrowserSidebarTabListItemPolicy {
    static func items(for tabs: [BrowserTab]) -> [BrowserSidebarTabListItem] {
        var items: [BrowserSidebarTabListItem] = []
        var foldedGroupIDs: Set<SplitGroupID> = []
        var index = tabs.startIndex

        while index < tabs.endIndex {
            guard let groupID = foldableGroupID(of: tabs[index]),
                !foldedGroupIDs.contains(groupID)
            else {
                items.append(.tab(tabs[index]))
                index += 1
                continue
            }

            var end = index
            while end < tabs.endIndex, foldableGroupID(of: tabs[end]) == groupID {
                end += 1
            }
            let run = Array(tabs[index..<end])
            if run.count >= BrowserSplitGroupPolicy.minimumRenderableMembers {
                items.append(.splitGroup(id: groupID, members: run))
                foldedGroupIDs.insert(groupID)
            } else {
                items.append(contentsOf: run.map { .tab($0) })
            }
            index = end
        }

        return items
    }

    /// The row a collapsed folder keeps visible for its resident selection.
    /// If that tab belongs to a renderable split, the whole group remains the
    /// visible subject; reducing it to `.tab` would claim only one pane was
    /// presented while the content area still showed every member.
    static func collapsedItem(
        keeping tabID: TabID,
        in tabs: [BrowserTab]
    ) -> BrowserSidebarTabListItem? {
        items(for: tabs).first { item in
            item.tabs.contains { $0.id == tabID }
        }
    }

    /// The group a tab could fold into, or `nil` when its placement bars it from
    /// membership at all. Pinned tabs are a grid of shortcuts rather than an
    /// ordered run, so they never fold even if a stale ID rode in on them.
    private static func foldableGroupID(of tab: BrowserTab) -> SplitGroupID? {
        guard BrowserSplitGroupPolicy.allowsMembership(placement: tab.placement)
        else { return nil }
        return tab.splitGroupID
    }
}
