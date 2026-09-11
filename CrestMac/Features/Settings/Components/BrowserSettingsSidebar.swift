import SwiftUI

struct BrowserSettingsSidebar: View {
    @Environment(\.locale) private var locale
    @Binding var navigation: BrowserSettingsNavigationState
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedDestination: BrowserSettingsDestination?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(searchPrompt, text: $navigation.searchText)
                    .textFieldStyle(.plain).focused($isSearchFocused)
                if !navigation.searchText.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { navigation.searchText = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(9)
            .background(BrowserSettingsCanvas.card, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)) }
            .padding(.horizontal, 12)
            .frame(height: 54)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(navigation.visibleDestinations(locale: locale)) { destination in
                        Button {
                            navigation.selection = destination
                        } label: {
                            BrowserSettingsDestinationRow(
                                destination: destination, isSelected: navigation.selection == destination
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        navigation.selection == destination ? destination.color.opacity(0.16) : .clear)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedDestination, equals: destination)
                        .accessibilityIdentifier("settings-\(destination.rawValue)")
                    }
                }.padding(10)
            }
            .onMoveCommand { direction in
                guard focusedDestination != nil else { return }
                let choices = navigation.visibleDestinations(locale: locale)
                guard let index = choices.firstIndex(of: navigation.selection) else { return }
                let offset = direction == .down ? 1 : direction == .up ? -1 : 0
                let next = choices[min(max(index + offset, 0), choices.count - 1)]
                focusedDestination = next
                navigation.selection = next
            }
        }
        .background(BrowserSettingsCanvas.background)
    }

    private var searchPrompt: LocalizedStringKey {
        navigation.selection == .passwords ? "Search passwords" : "Search settings"
    }
}
