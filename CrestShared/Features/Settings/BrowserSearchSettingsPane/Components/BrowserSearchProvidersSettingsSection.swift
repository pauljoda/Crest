import SwiftUI

/// Every search provider the device offers, one section for each kind: each
/// provider collapsed to its icon, main shortcut and switch until the person
/// opens it to its options and edits. The person may add their own and
/// return the built-ins to how they ship.
struct BrowserSearchProvidersSettingsSection: View {
    let catalog: BrowserSearchCatalog
    var profileID: UUID? = nil

    @State private var editing: BrowserSearchProviderDraft?
    @State private var confirmsResetting = false
    /// The providers the person opened, by name; every one starts closed.
    @State private var expandedNames: Set<String> = []

    var body: some View {
        ForEach(SearchProviderKind.all, id: \.self) { kind in
            Section {
                ForEach(catalog.providers(of: kind)) { provider in
                    BrowserSearchProviderRow(
                        provider: provider, catalog: catalog, profileID: profileID, isExpanded: expanded(provider)
                    ) {
                        editing = BrowserSearchProviderDraft(provider, catalog: catalog)
                    }
                }
            } header: {
                Text(kind.title)
            }
        }

        Section {
            Button("Add Provider…") {
                editing = .adding
            }
            .accessibilityIdentifier("add-search-provider")
            Button("Restore Defaults…") {
                confirmsResetting = true
            }
            .accessibilityIdentifier("restore-search-providers")
        }
        .sheet(item: $editing) { draft in
            BrowserSearchProviderEditor(draft: draft, catalog: catalog, profileID: profileID)
        }
        .confirmationDialog("Restore the built-in providers?", isPresented: $confirmsResetting) {
            Button("Restore Defaults", role: .destructive) { catalog.reset() }
        } message: {
            Text("Shortcuts and options you changed go back to how they ship. Providers you added stay.")
        }
    }

    private func expanded(_ provider: SearchProvider) -> Binding<Bool> {
        Binding {
            expandedNames.contains(provider.name)
        } set: { isExpanded in
            if isExpanded {
                expandedNames.insert(provider.name)
            } else {
                expandedNames.remove(provider.name)
            }
        }
    }
}
