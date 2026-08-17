import SwiftUI

struct SavedFolderTabRow: View {
    let configuration: SavedFolderGroupConfiguration
    let tab: BrowserTab
    let isLoaded: Bool
    let unload: (TabID) -> Void

    var body: some View {
        SidebarTabRow(
            tab: tab,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID,
            isSelected: tab.id == configuration.selectedTabID,
            canClose: false,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            presentSelectedPage: {
                configuration.pages.select(session: configuration.browser.session)
            },
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: {
                configuration.tabActions.pullNewIcon(for: tab.id)
            },
            restoreSavedLocation: {
                configuration.tabActions.restoreSavedLocation(for: tab.id)
            }
        )
        .padding(.leading, configuration.rowLeadingInset)
    }
}
