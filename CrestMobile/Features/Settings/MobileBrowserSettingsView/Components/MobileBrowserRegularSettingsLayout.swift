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
            MobileBrowserSettingsDestinationView(
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

#Preview("Regular Mobile Settings", traits: .fixedLayout(width: 1_024, height: 768)) {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserRegularSettingsLayout(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        dataDeleter: fixture.pages,
        selection: .constant(.general),
        searchText: .constant("")
    )
    .environment(fixture.cloudSync)
    .environment(fixture.onboardingCoordinator)
}
