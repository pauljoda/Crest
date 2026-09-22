import SwiftUI

struct BrowserSearchEngineEditor: View {
    private enum Field: Hashable {
        case name
        case searchURL
        case suggestionURL
    }

    let request: BrowserSearchEngineEditorRequest
    let dismissKeyboard: @MainActor () -> Void
    let keyboardDismissal: BrowserSearchEngineKeyboardDismissal
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
        keyboardDismissal: BrowserSearchEngineKeyboardDismissal,
        save: @escaping (BrowserCustomSearchProvider) throws -> Void
    ) {
        self.request = request
        self.dismissKeyboard = dismissKeyboard
        self.keyboardDismissal = keyboardDismissal
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
                CrestSettingsSectionHeading(title: "Search Engine", systemImage: "magnifyingglass")
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
                CrestSettingsSectionHeading(title: "Suggestions (Optional)", systemImage: "text.bubble")
            } footer: {
                Text(
                    "The endpoint must return an OpenSearch JSON array. Leave this blank when the engine does not offer suggestions."
                )
            }
        }
        .navigationTitle(request.isNew ? "Add Search Engine" : "Edit Search Engine")
        .onAppear { keyboardDismissal.cancel() }
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
            let custom = BrowserCustomSearchProvider(
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
        // The manager remains alive after this editor is popped or dismissed.
        keyboardDismissal.schedule(dismissKeyboard)
        dismiss()
    }
}
