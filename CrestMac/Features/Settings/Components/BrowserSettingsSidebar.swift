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
            prompt: "Search settings"
        )
        .searchFocused($isSearchFocused)
    }
}

#Preview("Settings Sidebar") {
    @Previewable @State var navigation = BrowserSettingsNavigationState()
    BrowserSettingsSidebar(navigation: $navigation)
        .frame(width: 240, height: 520)
}
