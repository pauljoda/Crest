import SwiftUI

struct MobileBrowserRegularSettingsLayout: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String
    let dismiss: (() -> Void)?
    /// The section a section row opens its page at.
    @State private var requestedSection: BrowserSettingsSection?

    var body: some View {
        NavigationSplitView {
            MobileBrowserSettingsDestinationList(
                selection: $selection,
                searchText: $searchText,
                requestedSection: $requestedSection,
                state: browser.core.state
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
            .navigationTitle(Text(selection.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { MobileBrowserSettingsToolbar(dismiss: dismiss) }
            .environment(\.browserSettingsSectionRequest, $requestedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
