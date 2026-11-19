import SwiftUI

/// Setup's last step, the choices made once before Crest starts: Crest as
/// the default browser, the search every Space follows, and how much ad
/// blocking blocks. Each takes effect at once, as it does in Settings, where
/// each can change later.
struct BrowserSetupHomePage: View {
    // MARK: - Variables

    let core: CrestCore
    @State private var catalog: BrowserSearchCatalog

    private var defaultProvider: Binding<SearchProvider?> {
        Binding {
            catalog.defaultProvider
        } set: { provider in
            guard let provider else { return }
            try? catalog.setDefault(provider)
        }
    }

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
        _catalog = State(initialValue: BrowserSearchCatalog(core: core))
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Form {
            BrowserDefaultBrowserSection {
                BrowserSetupPageHeading("Make It Home")
            }
            Section {
                Picker("Search with", selection: defaultProvider) {
                    ForEach(catalog.defaultChoices) { provider in
                        BrowserSearchProviderIdentityLabel(provider: provider, profileID: nil)
                            .tag(Optional(provider))
                    }
                }
                .accessibilityIdentifier("setup-default-search")
            } header: {
                CrestSettingsSectionHeading(title: "Search")
            }
            BrowserAdBlockingLevelSection(core: core, errorDescription: nil, title: "Ad Blocking")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
