import SwiftUI

struct MobileBrowserCompactSettingsLayout: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var searchText: String

    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List(filteredDestinations) { destination in
                NavigationLink(value: destination) {
                    MobileSettingsDestinationRow(destination: destination)
                }
                .accessibilityIdentifier("settings-\(destination.rawValue)")
            }
            .navigationTitle("Settings")
            .searchable(text: $searchText, prompt: "Search settings")
            .navigationDestination(for: BrowserSettingsDestination.self) {
                destination in
                MobileBrowserSettingsDestinationPage(
                    destination: destination,
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter
                )
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        MobileSettingsDestinationFilter.destinations(
            matching: searchText,
            locale: locale
        )
    }
}
