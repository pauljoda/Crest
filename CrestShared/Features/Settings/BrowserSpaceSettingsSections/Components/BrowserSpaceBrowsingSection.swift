import SwiftUI

/// A Space's search engine, suggestion privacy choice, and current-tab cleanup.
struct BrowserSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: BrowserSpace

    @State private var presentedSearchEngineSheet: BrowserSearchEngineSheet?

    var body: some View {
        Section("Browsing") {
            Picker(
                "Search engine",
                selection: browser.browsingPreferenceBinding(
                    \.searchProvider,
                    in: space
                )
            ) {
                ForEach(currentPreferences.availableSearchProviders) { provider in
                    BrowserSearchProviderIdentityLabel(
                        provider: provider,
                        profileID: currentSpace.profile.id
                    )
                    .tag(provider)
                }
            }
            .accessibilityIdentifier("space-search-provider")

            Button("Manage Search Engines…", systemImage: "magnifyingglass") {
                presentedSearchEngineSheet = .manager
            }
            .accessibilityIdentifier("manage-search-providers")

            Toggle(
                "Search suggestions",
                isOn: browser.browsingPreferenceBinding(
                    \.searchSuggestionsEnabled,
                    in: space
                )
            )
            .accessibilityIdentifier("space-search-suggestions")

            Text(
                "When enabled, typed searches are sent to this Space’s search engine after a short delay. Crest never requests suggestions in Private Browsing."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Picker(
                "Archive current tabs",
                selection: browser.browsingPreferenceBinding(
                    \.currentTabCleanupPolicy,
                    in: space
                )
            ) {
                ForEach(BrowserCurrentTabCleanupPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .accessibilityIdentifier("space-tab-cleanup-policy")

            Button("Clean Up Eligible Tabs Now", systemImage: "archivebox") {
                browser.cleanupCurrentTabs(in: space.id)
            }
            .disabled(
                currentSpace.browsingPreferences.currentTabCleanupPolicy
                    == .never
            )

            Text(
                "This policy applies only to \(currentSpace.name). Eligible tabs remain recoverable from Archive."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $presentedSearchEngineSheet) { _ in
            BrowserSearchEngineManager(browser: browser, space: space)
        }
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }

    private var currentPreferences: BrowserSpaceBrowsingPreferences {
        currentSpace.browsingPreferences
    }
}

private enum BrowserSearchEngineSheet: String, Identifiable {
    case manager
    var id: String { rawValue }
}

private struct BrowserSearchEngineManager: View {
    let browser: BrowserStore
    let space: BrowserSpace

    @Environment(\.dismiss) private var dismiss
    @State private var editorRequest: BrowserSearchEngineEditorRequest?
    @State private var pendingDeletion: BrowserCustomSearchProvider?

    var body: some View {
        NavigationStack {
            List {
                Section("Built-In") {
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
                        Text("Custom")
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
            .navigationTitle("Search Engines")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .browserSearchEngineSheetSizing(minWidth: 480, minHeight: 460)
        .sheet(item: $editorRequest) { request in
            BrowserSearchEngineEditor(request: request) { custom in
                try save(custom, selectsProvider: request.isNew)
            }
        }
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
            HStack {
                BrowserSearchProviderIdentityLabel(
                    provider: provider,
                    profileID: space.profile.id
                )
                Spacer()
                if preferences.searchProvider.id == provider.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
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
                HStack {
                    BrowserSearchProviderIdentityLabel(
                        provider: custom.provider,
                        profileID: space.profile.id
                    )
                    Spacer()
                    if preferences.searchProvider.id == .custom(custom.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
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

private struct BrowserSearchEngineEditorRequest: Identifiable {
    let id: UUID
    let name: String
    let searchURLTemplate: String
    let suggestionURLTemplate: String
    let isNew: Bool

    static func new() -> Self {
        Self(
            id: UUID(),
            name: "",
            searchURLTemplate: "",
            suggestionURLTemplate: "",
            isNew: true
        )
    }

    static func edit(_ provider: BrowserCustomSearchProvider) -> Self {
        Self(
            id: provider.id,
            name: provider.name,
            searchURLTemplate: provider.searchURLTemplate,
            suggestionURLTemplate: provider.suggestionURLTemplate ?? "",
            isNew: false
        )
    }
}

private struct BrowserSearchEngineEditor: View {
    let request: BrowserSearchEngineEditorRequest
    let save: (BrowserCustomSearchProvider) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var searchURLTemplate: String
    @State private var suggestionURLTemplate: String
    @State private var errorMessage: String?

    init(
        request: BrowserSearchEngineEditorRequest,
        save: @escaping (BrowserCustomSearchProvider) throws -> Void
    ) {
        self.request = request
        self.save = save
        _name = State(initialValue: request.name)
        _searchURLTemplate = State(initialValue: request.searchURLTemplate)
        _suggestionURLTemplate = State(initialValue: request.suggestionURLTemplate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("custom-search-provider-name")
                    TextField("Search URL", text: $searchURLTemplate)
                        .textContentType(.URL)
                        .accessibilityIdentifier("custom-search-provider-url")
                } header: {
                    Text("Search Engine")
                } footer: {
                    Text(
                        "Use exactly one %s or {searchTerms} where the encoded search should appear. HTTPS is required."
                    )
                }

                Section {
                    TextField("Suggestion URL", text: $suggestionURLTemplate)
                        .textContentType(.URL)
                        .accessibilityIdentifier("custom-search-suggestion-url")
                } header: {
                    Text("Suggestions (Optional)")
                } footer: {
                    Text(
                        "The endpoint must return an OpenSearch JSON array. Leave this blank when the engine does not offer suggestions."
                    )
                }
            }
            .navigationTitle(request.isNew ? "Add Search Engine" : "Edit Search Engine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProvider() }
                        .accessibilityIdentifier("save-custom-search-provider")
                }
            }
        }
        .browserSearchEngineSheetSizing(minWidth: 440, minHeight: 360)
        .alert(
            "Couldn’t Save Search Engine",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                verbatim: errorMessage
                    ?? String(
                        localized: "Check the search engine details and try again."
                    )
            )
        }
    }

    private func saveProvider() {
        do {
            let custom = try BrowserCustomSearchProvider(
                id: request.id,
                name: name,
                searchURLTemplate: searchURLTemplate,
                suggestionURLTemplate: suggestionURLTemplate
            )
            try save(custom)
            dismiss()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func browserSearchEngineSheetSizing(
        minWidth: CGFloat,
        minHeight: CGFloat
    ) -> some View {
        #if os(macOS)
            frame(minWidth: minWidth, minHeight: minHeight)
        #else
            presentationDetents([.medium, .large])
        #endif
    }
}
