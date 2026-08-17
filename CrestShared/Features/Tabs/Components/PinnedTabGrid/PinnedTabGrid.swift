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
    var usesNativeNavigationTransition = false

    var body: some View {
        PinnedTabGridContent(grid: self)
    }
}
