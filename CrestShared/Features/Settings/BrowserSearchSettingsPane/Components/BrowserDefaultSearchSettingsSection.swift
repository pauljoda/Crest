import SwiftUI

/// The search every Space follows unless it chose its own, the one private
/// windows follow, suggestions, and the independent Tab and Space provider triggers.
struct BrowserDefaultSearchSettingsSection: View {
    // MARK: - Variables

    @Bindable var preferences: BrowserAppPreferenceStore
    let catalog: BrowserSearchCatalog
    var profileID: UUID? = nil

    private var defaultProvider: Binding<SearchProvider?> {
        Binding {
            catalog.defaultProvider
        } set: { provider in
            guard let provider else { return }
            try? catalog.setDefault(provider)
        }
    }

    private var privateProvider: Binding<SearchProvider?> {
        Binding {
            catalog.privateDefaultProvider
        } set: { provider in
            guard let provider else { return }
            try? catalog.setPrivateDefault(provider)
        }
    }

    private var suggestions: Binding<Bool> {
        Binding {
            catalog.suggestionsEnabled
        } set: {
            catalog.setSuggestionsEnabled($0)
        }
    }

    var body: some View {
        Section {
            Picker("Default search", selection: defaultProvider) {
                ForEach(catalog.defaultChoices) { provider in
                    BrowserSearchProviderIdentityLabel(provider: provider, profileID: profileID)
                        .tag(Optional(provider))
                }
            }
            .accessibilityIdentifier("default-search")

            Picker("Private windows", selection: privateProvider) {
                ForEach(catalog.defaultChoices) { provider in
                    BrowserSearchProviderIdentityLabel(provider: provider, profileID: profileID)
                        .tag(Optional(provider))
                }
            }
            .accessibilityIdentifier("private-search")

            Toggle("Search suggestions", isOn: suggestions)
                .accessibilityIdentifier("default-search-suggestions")

            Toggle(isOn: $preferences.palette.searchesSitesWithTab) {
                Text("Tab selects a search provider")
                Text("When off, Tab cycles suggestions.")
            }
            .accessibilityIdentifier("palette-tab-to-search")

            Picker("Space selects a provider", selection: $preferences.palette.providerSpaceTrigger) {
                ForEach(SearchProviderSpaceTrigger.all, id: \.self) { trigger in
                    Text(trigger.title).tag(trigger)
                }
            }
            .accessibilityIdentifier("palette-space-to-search")
            Text(preferences.palette.providerSpaceTrigger.example).crestFormFootnote()
        } header: {
            Text("Search")
        } footer: {
            CrestFormFootnote("Search suggestions send what you type to the search engine.")
        }
    }
}
