import SwiftUI

struct MobileBrowserSettingsDestinationList: View {
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
                ForEach(filteredDestinations) { destination in
                    Button {
                        selection = destination
                    } label: {
                        MobileSettingsDestinationRow(destination: destination)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-\(destination.rawValue)")
                    .listRowBackground(rowBackground(for: destination))
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(
                        selection == destination ? .isSelected : []
                    )
                }
            } header: {
                if !usesLiveSidebar {
                    Text(ProductIdentity.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSpacing(4)
        .scrollContentBackground(.hidden)
        .background(sidebarBackground)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        .searchable(text: $searchText, prompt: "Search settings")
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        MobileSettingsDestinationFilter.destinations(
            matching: searchText,
            locale: locale
        )
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if usesLiveSidebar {
            BrowserSettingsCanvas.background
        } else {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(
                        BrowserVisualAccessibilityPolicy.atmosphereOpacity(
                            0.1,
                            reduceTransparency: reduceTransparency
                        )
                    ),
                    Color(uiColor: .systemGroupedBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func rowBackground(
        for destination: BrowserSettingsDestination
    ) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(selection == destination ? destination.color.opacity(0.16) : .clear)
            .padding(.vertical, 2)
    }
}
