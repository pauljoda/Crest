import Foundation

/// Stable identity for a sidebar tab-list row, so `ForEach` keeps a group's row
/// alive as members come and go and never confuses a group with a tab.
enum BrowserSidebarTabListItemID: Hashable, Sendable {
    case tab(TabID)
    case splitGroup(SplitGroupID)
}
