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

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    var body: some View {
        if isSelected != false {
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
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}
