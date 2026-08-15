import SwiftUI

struct SpaceSidebarUtilityContent: View {
    let surface: BrowserUtilitySurface
    let space: BrowserSpace
    @Binding var searchText: String
    @Binding var filter: BrowserUtilityListFilter
    let commandSurfaceNamespace: Namespace.ID
    let downloads: [BrowserDownloadItem]
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: () -> Void
    let clearHistory: () -> Void

    var body: some View {
        BrowserUtilitySearchToolbar(
            surface: surface,
            searchText: $searchText,
            filter: $filter,
            morphNamespace: commandSurfaceNamespace,
            morphID: "crest-address-command-\(space.id)",
            clearHistory: clearHistory
        )
        .padding(.horizontal, BrowserChromeLayout.sidebarHorizontalInset)
        .padding(.bottom, CrestSpacing.extraSmall)
        .transition(.opacity.combined(with: .move(edge: .trailing)))

        BrowserUtilityListContent(
            surface: surface,
            space: space,
            downloads: downloads,
            searchText: searchText,
            filter: filter,
            actions: actions,
            dismissOnBlankSpace: dismissOnBlankSpace
        )
        .transition(.opacity)
    }
}

#Preview("Space Sidebar Utility Content") {
    @Previewable @State var searchText = ""
    @Previewable @State var filter = BrowserUtilityListFilter.all
    @Previewable @Namespace var commandSurfaceNamespace
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let pages = BrowserSidebarPreviewFixture.makePages()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    SpaceSidebarUtilityContent(
        surface: .history,
        space: BrowserSidebarPreviewFixture.space,
        searchText: $searchText,
        filter: $filter,
        commandSurfaceNamespace: commandSurfaceNamespace,
        downloads: [],
        actions: BrowserSidebarPreviewFixture.makeUtilityActions(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ),
        dismissOnBlankSpace: {},
        clearHistory: {}
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 540)
}
