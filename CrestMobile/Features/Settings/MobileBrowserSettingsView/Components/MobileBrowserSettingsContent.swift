import SwiftUI

struct MobileBrowserSettingsContent: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                MobileBrowserRegularSettingsLayout(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    selection: $selection,
                    searchText: $searchText
                )
            } else {
                MobileBrowserCompactSettingsLayout(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    searchText: $searchText
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismiss.callAsFunction)
            }
        }
        .presentationSizing(.fitted)
    }
}

#Preview("Mobile Settings Content") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserSettingsContent(
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
