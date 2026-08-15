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

#Preview("Pinned Tab Grid", traits: .sizeThatFitsLayout) {
    @Previewable @State var selectedIndex = 0
    let fixture = PinnedTabGridPreviewFixture()

    PinnedTabGrid(
        tabs: fixture.pinnedTabs,
        assignment: fixture.assignment,
        selectedTabID: fixture.pinnedTabs[selectedIndex].id,
        select: { assignment in
            selectedIndex =
                fixture.pinnedTabs.firstIndex {
                    $0.id == assignment.tabID
                } ?? 0
        },
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess,
        isLoaded: { $0.tabID == fixture.pinnedTab.id },
        unload: { _ in },
        pullNewIcon: { _ in },
        restoreSavedLocation: { _ in },
        siteThemeAccent: { _ in
            BrowserTabIconAccent(red: 0.31, green: 0.58, blue: 0.96)
        }
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
    .padding()
}
