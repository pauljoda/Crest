import Foundation

/// The two halves of opening a tab from the sidebar, kept in one order.
///
/// Selection has to land before presentation, because the page a shell brings
/// on screen is whichever one the session now points at. Splitting the pair
/// across call sites is how a row ends up presenting the tab it just left.
enum BrowserTabActivationPolicy {
    static func activate(
        _ tabID: TabID,
        selectTab: (TabID) -> Void,
        presentPage: () -> Void
    ) {
        selectTab(tabID)
        presentPage()
    }
}
