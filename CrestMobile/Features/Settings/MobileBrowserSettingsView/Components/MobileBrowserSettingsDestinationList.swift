import SwiftUI

struct MobileBrowserSettingsDestinationList: View {
    /// How wide the list's column may be beside a page on iPad.
    private static let minimumColumnWidth: CGFloat = 220
    private static let idealColumnWidth: CGFloat = 250
    private static let maximumColumnWidth: CGFloat = 290

    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String
    /// The section a section row opens its page at.
    @Binding var requestedSection: BrowserSettingsSection?
    /// The read model whose engines say which destinations exist.
    let state: CoreState

    @Environment(\.locale) private var locale

    // Rows are buttons rather than the list's own selection: a selection
    // list inside the browser's page surface never receives the tap.
    var body: some View {
        List {
            Section {
                MobileSettingsBuildHeader()
            }
            Section {
                ForEach(filteredDestinations) { destination in
                    Button {
                        // A page row opens the page as it always does; only a
                        // section row opens it at a section.
                        requestedSection = nil
                        selection = destination
                    } label: {
                        MobileSettingsDestinationRow(destination: destination)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // The design system's row surface marks the page that's
                    // showing, and answers the pointer and a press.
                    .buttonStyle(
                        CrestFormRowButtonStyle(isSelected: selection == destination, cornerRadius: CrestRadius.control)
                    )
                    .accessibilityIdentifier(BrowserMobileAccessibilityID.settingsDestination(destination))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                    ForEach(listedSections(of: destination)) { section in
                        Button {
                            requestedSection = section
                            selection = destination
                        } label: {
                            MobileSettingsSectionResultRow(section: section)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(CrestFormRowButtonStyle(isSelected: false, cornerRadius: CrestRadius.control))
                        .accessibilityIdentifier("settings-result-\(destination.name)-\(section.name)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSpacing(CrestSpacing.extraSmall)
        .navigationSplitViewColumnWidth(
            min: Self.minimumColumnWidth, ideal: Self.idealColumnWidth, max: Self.maximumColumnWidth
        )
        .searchable(text: $searchText, prompt: "Search settings")
    }

    /// The sections of `destination` a search lists under its row, once the
    /// search is long enough to mean something.
    private func listedSections(of destination: BrowserSettingsDestination) -> [BrowserSettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        return destination.sections(matching: query, locale: locale, in: state)
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        BrowserSettingsDestination.visible(
            matching: searchText,
            locale: locale,
            in: state
        )
    }
}
