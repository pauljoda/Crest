import SwiftUI

struct MobileBrowserCompactSettingsLayout: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var searchText: String
    @Binding var path: [BrowserSettingsDestination]
    let dismiss: (() -> Void)?

    @Environment(\.locale) private var locale
    /// The section a section row pushes its page open at.
    @State private var requestedSection: BrowserSettingsSection?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    MobileSettingsBuildHeader()
                }
                Section {
                    ForEach(filteredDestinations) { destination in
                        NavigationLink(value: destination) {
                            MobileSettingsDestinationRow(destination: destination)
                        }
                        .accessibilityIdentifier(BrowserMobileAccessibilityID.settingsDestination(destination))
                        ForEach(listedSections(of: destination)) { section in
                            Button {
                                requestedSection = section
                                path.append(destination)
                            } label: {
                                MobileSettingsSectionResultRow(section: section)
                            }
                            // A list tints a button's label with the accent;
                            // a section row reads as secondary text instead.
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-result-\(destination.name)-\(section.name)")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { MobileBrowserSettingsToolbar(dismiss: dismiss) }
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
                .navigationTitle(Text(destination.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { MobileBrowserSettingsToolbar(dismiss: dismiss) }
                .environment(\.browserSettingsSectionRequest, $requestedSection)
            }
        }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sections of `destination` a search lists under its row, once the
    /// search is long enough to mean something.
    private func listedSections(of destination: BrowserSettingsDestination) -> [BrowserSettingsSection] {
        guard query.count >= 2 else { return [] }
        return destination.sections(matching: query, locale: locale, in: browser.core.state)
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        BrowserSettingsDestination.visible(
            matching: searchText,
            locale: locale,
            in: browser.core.state
        )
    }
}
