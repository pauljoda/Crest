import SwiftUI

struct PinnedTabGrid: View {
    let tabs: [BrowserTab]
    let assignment: BrowserSpaceRuntimeAssignment
    let selectedTabID: TabID?
    let select: (BrowserTabRuntimeAssignment) -> Void
    var moveTab: ((BrowserTabDragItem, TabID?) -> Bool)? = nil
    var dragState: BrowserTabDragState? = nil
    var browser: BrowserStore? = nil
    var spaceAccess: BrowserSpaceAccessController? = nil
    var isLoaded: (BrowserTabRuntimeAssignment) -> Bool = { _ in true }
    var unload: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var pullNewIcon: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var restoreSavedLocation: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var siteThemeAccent: (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? = {
        _ in nil
    }
    var promotionNamespace: Namespace.ID? = nil
    /// What the hosting shell can do. The grid reads one thing from it: which
    /// promotion anchor — if any — a tile may claim, which is a presentation
    /// transform over the view the drag interaction lifts. See
    /// `BrowserPinnedTabPromotionPolicy`.
    var capabilities = BrowserInteractionCapabilities()

    var body: some View {
        PinnedTabGridContent(grid: self)
    }
}
