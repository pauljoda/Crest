import Foundation

/// One row a sidebar tab list renders: an ordinary tab, or a split group folded
/// into a single stacked row.
///
/// The sidebar draws groups as one row so a split reads — and moves — as one
/// thing. `BrowserSidebarTabListItemPolicy` is the only place that decides which
/// tabs fold, so macOS and mobile cannot disagree about what a group looks like.
enum BrowserSidebarTabListItem: Equatable, Identifiable, Sendable {
    case tab(BrowserTab)
    case splitGroup(id: SplitGroupID, members: [BrowserTab])

    var id: BrowserSidebarTabListItemID {
        switch self {
        case let .tab(tab): .tab(tab.id)
        case let .splitGroup(id, _): .splitGroup(id)
        }
    }

    /// Every tab this row stands for, in session order. A plain tab answers
    /// itself, so counts and identities can be derived without unwrapping the
    /// case.
    var tabs: [BrowserTab] {
        switch self {
        case let .tab(tab): [tab]
        case let .splitGroup(_, members): members
        }
    }

    /// Row identity for collection-motion keying, in the same string form the
    /// sidebar's saved section already uses for tabs and folders. Folding a run
    /// into a group replaces several tab identities with one group identity,
    /// which is what makes the change animate.
    var collectionMotionID: String {
        switch self {
        case let .tab(tab): "tab-\(tab.id.rawValue.uuidString)"
        case let .splitGroup(id, _): "split-\(id.rawValue.uuidString)"
        }
    }
}
