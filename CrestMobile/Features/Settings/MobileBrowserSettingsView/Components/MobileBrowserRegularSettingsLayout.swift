import SwiftUI

struct MobileBrowserRegularSettingsLayout: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String

    var body: some View {
        NavigationSplitView {
            MobileBrowserSettingsDestinationList(
                selection: $selection,
                searchText: $searchText
            )
            .navigationTitle("Settings")
        } detail: {
            MobileBrowserSettingsDestinationPage(
                destination: selection,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
