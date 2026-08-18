import SwiftUI

struct SpaceSwitcher: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void
    let commonListsAreExpanded: Bool
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    var body: some View {
        SpaceSwitcherContent(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            selectSpace: selectSpace,
            sidebarToggleAction: sidebarToggleAction,
            toggleSidebar: toggleSidebar,
            commonListsAreExpanded: commonListsAreExpanded,
            toggleCommonLists: toggleCommonLists,
            recordCommonListsTriggerFrame: recordCommonListsTriggerFrame
        )
        .padding(.horizontal, 12)
        .frame(height: 50)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}
