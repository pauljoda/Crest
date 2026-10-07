import SwiftUI

struct BrowserSearchEngineManager: View {
    let browser: BrowserStore
    let space: SpaceModel
    let dismissKeyboard: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editorRequest: BrowserSearchEngineEditorRequest?
    @State private var pendingDeletion: CustomSearchProvider?
    @State private var keyboardDismissal = BrowserSearchEngineKeyboardDismissal()

    init(
        browser: BrowserStore,
        space: SpaceModel,
        dismissKeyboard: @escaping @MainActor () -> Void = {}
    ) {
        self.browser = browser
        self.space = space
        self.dismissKeyboard = dismissKeyboard
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(SearchProvider.all) { provider in
                        providerRow(provider)
                    }
                }

                Section {
                    if preferences.customSearchProviders.isEmpty {
                        Text("No custom search engines")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preferences.customSearchProviders) { custom in
                            customProviderRow(custom)
                        }
                    }
                } header: {
                    HStack {
                        CrestSettingsSectionHeading(title: "Custom")
                        Spacer()
                        Button {
                            editorRequest = .new()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Add Search Engine")
                        .accessibilityIdentifier("add-custom-search-provider")
                    }
                }

                Section {
                } footer: {
                    CrestFormFootnote("Don’t put sign-in tokens in a search URL. It syncs with this Space.")
                }
            }
            .browserSearchEngineEditorPresentation(item: $editorRequest) { request in
                BrowserSearchEngineEditor(
                    request: request,
                    dismissKeyboard: dismissKeyboard,
                    keyboardDismissal: keyboardDismissal
                ) { custom in
                    try save(custom, selectsProvider: request.isNew)
                }
            }
            .navigationTitle("Search Engines")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .browserSearchEngineSheetSizing(.manager)
        .onDisappear { keyboardDismissal.cancel() }
        .confirmationDialog(
            "Remove Search Engine?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { custom in
            Button("Remove \(custom.name)", role: .destructive) {
                remove(custom)
            }
            Button("Cancel", role: .cancel) {}
        } message: { custom in
            Text(
                verbatim:
                    preferences.searchProvider == SearchProvider(custom: custom)
                    ? String(localized: "Google will become this Space’s search engine.")
                    : String(
                        localized: "This removes \(custom.name) from this Space."
                    )
            )
        }
    }

    private var preferences: BrowsingPreferences {
        space.settings.browsingPreferences
    }

    private func providerRow(_ provider: SearchProvider) -> some View {
        Button {
            select(provider)
        } label: {
            BrowserSearchEngineProviderLabel(
                provider: provider, profileID: space.profileID,
                isSelected: preferences.searchProvider == provider)
        }
        .buttonStyle(.plain)
    }

    private func customProviderRow(
        _ custom: CustomSearchProvider
    ) -> some View {
        HStack {
            Button {
                select(SearchProvider(custom: custom))
            } label: {
                BrowserSearchEngineProviderLabel(
                    provider: SearchProvider(custom: custom), profileID: space.profileID,
                    isSelected: preferences.searchProvider == SearchProvider(custom: custom)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu("More", systemImage: "ellipsis") {
                Button("Edit", systemImage: "pencil") {
                    editorRequest = .edit(custom)
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingDeletion = custom
                }
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityElement(children: .contain)
    }

    private func select(_ provider: SearchProvider) {
        var updated = preferences
        updated.searchProvider = provider
        browser.updateBrowsingPreferences(updated, in: space.id)
    }

    private func save(
        _ engine: CustomSearchEngine,
        selectsProvider: Bool
    ) throws {
        try browser.upsertCustomSearchProvider(engine, selects: selectsProvider, in: space.id)
    }

    private func remove(_ custom: CustomSearchProvider) {
        browser.removeCustomSearchProvider(id: custom.id, in: space.id)
        pendingDeletion = nil
    }
}
