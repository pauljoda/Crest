import SwiftUI

struct MobileBrowserSettingsDestinationList: View {
    /// How wide the list's column may be beside a page on iPad.
    private static let minimumColumnWidth: CGFloat = 220
    private static let idealColumnWidth: CGFloat = 250
    private static let maximumColumnWidth: CGFloat = 290

    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String
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

    private var filteredDestinations: [BrowserSettingsDestination] {
        BrowserSettingsDestination.visible(
            matching: searchText,
            locale: locale,
            in: state
        )
    }
}
