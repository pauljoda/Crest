import SwiftUI

struct BrowserSearchEngineManager: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let dismissKeyboard: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editorRequest: BrowserSearchEngineEditorRequest?
    @State private var pendingDeletion: BrowserCustomSearchProvider?
    @State private var keyboardDismissal = BrowserSearchEngineKeyboardDismissal()

    init(
        browser: BrowserStore,
        space: BrowserSpace,
        dismissKeyboard: @escaping @MainActor () -> Void = {}
    ) {
        self.browser = browser
        self.space = space
        self.dismissKeyboard = dismissKeyboard
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Built-In", systemImage: "magnifyingglass") {
                    ForEach(BrowserSearchProvider.allCases) { provider in
                        providerRow(provider)
                    }
                }

                Section {
                    if preferences.customSearchProviders.isEmpty {
                        ContentUnavailableView(
                            "No Custom Search Engines",
                            systemImage: "magnifyingglass",
                            description: Text(
                                "Add an HTTPS search URL containing %s or {searchTerms}."
                            )
                        )
                    } else {
                        ForEach(preferences.customSearchProviders) { custom in
                            customProviderRow(custom)
                        }
                    }
                } header: {
                    HStack {
                        CrestSettingsSectionHeading(title: "Custom", systemImage: "slider.horizontal.3")
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
                    Text(
                        "Custom engines belong to this Space and sync with it. Crest loads their favicon from the engine’s website; the image itself is not synced. Sign in on the engine’s website instead of putting a token in a URL template."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    preferences.searchProvider.id == .custom(custom.id)
                    ? String(localized: "Google will become this Space’s search engine.")
                    : String(
                        localized: "This removes \(custom.name) from this Space."
                    )
            )
        }
    }

    private var preferences: BrowserSpaceBrowsingPreferences {
        browser.liveSpace(space).browsingPreferences
    }

    private func providerRow(_ provider: BrowserSearchProvider) -> some View {
        Button {
            select(provider)
        } label: {
            BrowserSearchEngineProviderLabel(
                provider: provider, profileID: space.profile.id,
                isSelected: preferences.searchProvider.id == provider.id)
        }
        .buttonStyle(.plain)
    }

    private func customProviderRow(
        _ custom: BrowserCustomSearchProvider
    ) -> some View {
        HStack {
            Button {
                select(custom.provider)
            } label: {
                BrowserSearchEngineProviderLabel(
                    provider: custom.provider, profileID: space.profile.id,
                    isSelected: preferences.searchProvider.id == .custom(custom.id)
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

    private func select(_ provider: BrowserSearchProvider) {
        var updated = preferences
        updated.searchProvider = provider
        browser.updateBrowsingPreferences(updated, in: space.id)
    }

    private func save(
        _ custom: BrowserCustomSearchProvider,
        selectsProvider: Bool
    ) throws {
        var updated = preferences
        try updated.upsertCustomSearchProvider(custom)
        if selectsProvider {
            updated.searchProvider = custom.provider
        }
        browser.updateBrowsingPreferences(updated, in: space.id)
    }

    private func remove(_ custom: BrowserCustomSearchProvider) {
        var updated = preferences
        updated.removeCustomSearchProvider(id: custom.id)
        browser.updateBrowsingPreferences(updated, in: space.id)
        pendingDeletion = nil
    }
}
