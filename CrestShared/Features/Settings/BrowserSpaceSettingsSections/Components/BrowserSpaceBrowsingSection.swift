import SwiftUI

enum BrowserSpaceBrowsingPickerPresentationStyle: Equatable {
    case nativePicker
    case paddedMenu

    static var platformDefault: Self {
        #if os(macOS)
            .nativePicker
        #else
            .paddedMenu
        #endif
    }

    var dismissesKeyboardAfterSelection: Bool {
        self == .paddedMenu
    }
}

struct BrowserSpaceBrowsingPickerValueLayout: Equatable {
    let minimumLeadingGap: CGFloat
    let providerTextSpacing: CGFloat
    let disclosureSpacing: CGFloat
    let verticalPadding: CGFloat
    let providerTitleLineLimit: Int
    let minimumProviderTitleScale: CGFloat

    static let touch = Self(
        minimumLeadingGap: 16,
        providerTextSpacing: 10,
        disclosureSpacing: 8,
        verticalPadding: 5,
        providerTitleLineLimit: 1,
        minimumProviderTitleScale: 0.8
    )
}

/// A Space's search engine, suggestion privacy choice, and current-tab cleanup.
struct BrowserSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let manageSearchEngines: (() -> Void)?
    let dismissKeyboard: @MainActor () -> Void

    @State private var presentedSearchEngineSheet: BrowserSearchEngineSheet?

    init(
        browser: BrowserStore,
        space: BrowserSpace,
        manageSearchEngines: (() -> Void)? = nil,
        dismissKeyboard: @escaping @MainActor () -> Void = {}
    ) {
        self.browser = browser
        self.space = space
        self.manageSearchEngines = manageSearchEngines
        self.dismissKeyboard = dismissKeyboard
    }

    var body: some View {
        Section("Browsing") {
            searchProviderPicker

            Button("Manage Search Engines…", systemImage: "magnifyingglass") {
                requestSearchEngineManagement()
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

            cleanupPolicyPicker

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
            BrowserSearchEngineManager(
                browser: browser,
                space: space,
                dismissKeyboard: dismissKeyboard
            )
        }
    }

    func requestSearchEngineManagement() {
        guard let manageSearchEngines else {
            presentedSearchEngineSheet = .manager
            return
        }
        manageSearchEngines()
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }

    private var currentPreferences: BrowserSpaceBrowsingPreferences {
        currentSpace.browsingPreferences
    }

    private var searchProviderBinding: Binding<BrowserSearchProvider> {
        browser.browsingPreferenceBinding(\.searchProvider, in: space)
    }

    private var cleanupPolicyBinding: Binding<BrowserCurrentTabCleanupPolicy> {
        browser.browsingPreferenceBinding(\.currentTabCleanupPolicy, in: space)
    }

    private func selectSearchProviderFromMenu(
        _ provider: BrowserSearchProvider
    ) {
        searchProviderBinding.wrappedValue = provider
        dismissKeyboardAfterPickerSelection()
    }

    private func selectCleanupPolicyFromMenu(
        _ policy: BrowserCurrentTabCleanupPolicy
    ) {
        cleanupPolicyBinding.wrappedValue = policy
        dismissKeyboardAfterPickerSelection()
    }

    private func dismissKeyboardAfterPickerSelection() {
        let presentation = BrowserSpaceBrowsingPickerPresentationStyle.platformDefault
        guard presentation.dismissesKeyboardAfterSelection else { return }

        dismissKeyboard()
        let keyboardDismissal = BrowserSearchEngineEditorKeyboardDismissalStyle.platformDefault
        guard keyboardDismissal.repeatsDismissalAfterNavigation else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            dismissKeyboard()
        }
    }

    @ViewBuilder
    private var searchProviderPicker: some View {
        switch BrowserSpaceBrowsingPickerPresentationStyle.platformDefault {
        case .nativePicker:
            Picker("Search engine", selection: searchProviderBinding) {
                ForEach(currentPreferences.availableSearchProviders) { provider in
                    BrowserSearchProviderIdentityLabel(
                        provider: provider,
                        profileID: currentSpace.profile.id
                    )
                    .tag(provider)
                }
            }
            .accessibilityIdentifier("space-search-provider")
        case .paddedMenu:
            Menu {
                ForEach(currentPreferences.availableSearchProviders) { provider in
                    Button {
                        selectSearchProviderFromMenu(provider)
                    } label: {
                        Label {
                            Text(provider.title)
                        } icon: {
                            if provider.id == currentPreferences.searchProvider.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                BrowserSpaceBrowsingMenuLabel(
                    title: "Search engine",
                    layout: .touch
                ) {
                    HStack(spacing: BrowserSpaceBrowsingPickerValueLayout.touch.providerTextSpacing) {
                        BrowserSearchProviderIcon(
                            provider: currentPreferences.searchProvider,
                            profileID: currentSpace.profile.id,
                            size: BrowserSearchProviderIdentityLabelLayout.touch.iconSize
                        )
                        Text(currentPreferences.searchProvider.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(
                                BrowserSpaceBrowsingPickerValueLayout.touch
                                    .providerTitleLineLimit
                            )
                            .minimumScaleFactor(
                                BrowserSpaceBrowsingPickerValueLayout.touch
                                    .minimumProviderTitleScale
                            )
                            .allowsTightening(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Search engine")
            .accessibilityValue(currentPreferences.searchProvider.title)
            .accessibilityIdentifier("space-search-provider")
        }
    }

    @ViewBuilder
    private var cleanupPolicyPicker: some View {
        switch BrowserSpaceBrowsingPickerPresentationStyle.platformDefault {
        case .nativePicker:
            Picker("Archive current tabs", selection: cleanupPolicyBinding) {
                ForEach(BrowserCurrentTabCleanupPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .accessibilityIdentifier("space-tab-cleanup-policy")
        case .paddedMenu:
            Menu {
                ForEach(BrowserCurrentTabCleanupPolicy.allCases) { policy in
                    Button {
                        selectCleanupPolicyFromMenu(policy)
                    } label: {
                        Label {
                            Text(policy.title)
                        } icon: {
                            if policy == currentPreferences.currentTabCleanupPolicy {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                BrowserSpaceBrowsingMenuLabel(
                    title: "Archive current tabs",
                    layout: .touch
                ) {
                    Text(currentPreferences.currentTabCleanupPolicy.title)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Archive current tabs")
            .accessibilityValue(currentPreferences.currentTabCleanupPolicy.title)
            .accessibilityIdentifier("space-tab-cleanup-policy")
        }
    }
}

private struct BrowserSpaceBrowsingMenuLabel<Value: View>: View {
    let title: LocalizedStringKey
    let layout: BrowserSpaceBrowsingPickerValueLayout
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: layout.minimumLeadingGap)
            HStack(spacing: layout.disclosureSpacing) {
                value()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, layout.verticalPadding)
        .contentShape(.rect)
    }
}

private enum BrowserSearchEngineSheet: String, Identifiable {
    case manager
    var id: String { rawValue }
}

struct BrowserSearchEngineManager: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let dismissKeyboard: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editorRequest: BrowserSearchEngineEditorRequest?
    @State private var pendingDeletion: BrowserCustomSearchProvider?

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
            .browserSearchEngineEditorPresentation(item: $editorRequest) { request in
                BrowserSearchEngineEditor(
                    request: request,
                    dismissKeyboard: dismissKeyboard
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
        .browserSearchEngineSheetSizing(minWidth: 480, minHeight: 460)
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

enum BrowserSearchEngineEditorPresentationStyle: Equatable {
    case navigation
    case sheet

    static var platformDefault: Self {
        #if os(macOS)
            .sheet
        #else
            .navigation
        #endif
    }
}

enum BrowserSearchEngineEditorKeyboardDismissalStyle: Equatable {
    case focusOnly
    case resignFirstResponder

    static var platformDefault: Self {
        #if canImport(UIKit)
            .resignFirstResponder
        #else
            .focusOnly
        #endif
    }

    var repeatsDismissalAfterNavigation: Bool {
        self == .resignFirstResponder
    }
}

private struct BrowserSearchEngineEditorRequest: Hashable, Identifiable {
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
    private enum Field: Hashable {
        case name
        case searchURL
        case suggestionURL
    }

    let request: BrowserSearchEngineEditorRequest
    let dismissKeyboard: @MainActor () -> Void
    let save: (BrowserCustomSearchProvider) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var name: String
    @State private var searchURLTemplate: String
    @State private var suggestionURLTemplate: String
    @State private var errorMessage: String?

    init(
        request: BrowserSearchEngineEditorRequest,
        dismissKeyboard: @escaping @MainActor () -> Void,
        save: @escaping (BrowserCustomSearchProvider) throws -> Void
    ) {
        self.request = request
        self.dismissKeyboard = dismissKeyboard
        self.save = save
        _name = State(initialValue: request.name)
        _searchURLTemplate = State(initialValue: request.searchURLTemplate)
        _suggestionURLTemplate = State(initialValue: request.suggestionURLTemplate)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("custom-search-provider-name")
                TextField("Search URL", text: $searchURLTemplate)
                    .textContentType(.URL)
                    .focused($focusedField, equals: .searchURL)
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
                    .focused($focusedField, equals: .suggestionURL)
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
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismissEditor() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveProvider() }
                    .accessibilityIdentifier("save-custom-search-provider")
            }
        }
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
            dismissEditor()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func dismissEditor() {
        focusedField = nil
        dismissKeyboard()
        dismiss()

        let keyboardDismissal = BrowserSearchEngineEditorKeyboardDismissalStyle.platformDefault
        guard keyboardDismissal.repeatsDismissalAfterNavigation else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            dismissKeyboard()
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func browserSearchEngineEditorPresentation<
        Item: Hashable & Identifiable,
        Destination: View
    >(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        switch BrowserSearchEngineEditorPresentationStyle.platformDefault {
        case .navigation:
            navigationDestination(item: item, destination: destination)
        case .sheet:
            sheet(item: item) { item in
                NavigationStack {
                    destination(item)
                }
                .browserSearchEngineSheetSizing(minWidth: 440, minHeight: 360)
            }
        }
    }

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
