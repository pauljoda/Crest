import SwiftUI

struct MobileBrowserSettingsView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selection = BrowserSettingsDestination.general
    @State private var searchText = ""

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        dataDeleter: (any BrowserSpaceDataDeleting)? = nil
    ) {
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.dataDeleter = dataDeleter ?? pages
    }

    var body: some View {
        MobileBrowserSettingsContent(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            selection: $selection,
            searchText: $searchText
        )
    }
}

#Preview("Mobile Settings") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserSettingsView(
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess
    )
    .environment(fixture.cloudSync)
    .environment(fixture.onboardingCoordinator)
}
