import SwiftUI

struct BrowserSettingsSidebar: View {
    @Environment(\.locale) private var locale

    @Binding var navigation: BrowserSettingsNavigationState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List(selection: $navigation.selection) {
            ForEach(navigation.visibleDestinations(locale: locale)) { destination in
                BrowserSettingsDestinationRow(
                    destination: destination,
                    isSelected: navigation.selection == destination
                )
                .tag(destination)
                .accessibilityIdentifier("settings-\(destination.rawValue)")
                .listItemTint(destination.color)
                .tint(destination.color)
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $navigation.searchText,
            placement: .sidebar,
            prompt: Text(searchPrompt)
        )
        .searchFocused($isSearchFocused)
    }

    private var searchPrompt: LocalizedStringKey {
        navigation.selection == .passwords
            ? "Search passwords"
            : "Search settings"
    }
}
