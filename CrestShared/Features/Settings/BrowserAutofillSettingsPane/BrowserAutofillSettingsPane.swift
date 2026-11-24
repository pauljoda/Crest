import SwiftUI

/// Settings › Autofill: one place for what Crest fills into pages. The Space
/// picker chooses whose passwords show, with the codes their logins make;
/// addresses and payment cards are the person's, shared by every Space. Each
/// kind keeps its own searchable list and editor.
struct BrowserAutofillSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let layout: BrowserPasswordSettingsLayout
    @Binding var searchText: String
    var manage: (() -> Void)?
    /// The Space Settings was asked to open Autofill on.
    var requestedSpaceID: UUID?
    var requestRevision = 0
    var importFromAnotherBrowser: (() -> Void)?

    @State private var kind = BrowserAutofillKind.passwords
    @State private var pickedSpaceID: UUID?

    init(
        browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, layout: BrowserPasswordSettingsLayout,
        searchText: Binding<String>, manage: (() -> Void)? = nil, requestedSpaceID: UUID? = nil,
        requestRevision: Int = 0,
        importFromAnotherBrowser: (() -> Void)? = nil
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.layout = layout
        _searchText = searchText
        self.manage = manage
        self.requestedSpaceID = requestedSpaceID
        self.requestRevision = requestRevision
        self.importFromAnotherBrowser = importFromAnotherBrowser
        // Starts on a Space, so the lists load once rather than twice.
        _pickedSpaceID = State(initialValue: requestedSpaceID ?? browser.shownSpace?.id)
    }

    var body: some View {
        content
            .crestRepairsSpaceSelection($pickedSpaceID, in: browser)
            .onChange(of: requestRevision, initial: true) {
                if let requestedSpaceID {
                    pickedSpaceID = requestedSpaceID
                    kind = .passwords
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch kind.id {
        case BrowserAutofillKind.addresses.id:
            BrowserAddressSettingsPane(browser: browser) { header }
        case BrowserAutofillKind.cards.id:
            BrowserCardSettingsPane(browser: browser) { header }
        default:
            BrowserPasswordSettingsPane(
                browser: browser, spaceAccess: spaceAccess, layout: layout, searchText: $searchText, manage: manage,
                fixedSpaceID: pickedSpaceID
            ) { header }
            .importingFromAnotherBrowser(importFromAnotherBrowser)
        }
    }

    /// The Space whose passwords show, and what shows.
    private var header: some View {
        Section {
            // The choice spans the card rather than leaving room beside it.
            CrestFillingSegmentedPicker(title: "Show", choices: BrowserAutofillKind.all, selection: $kind) {
                String(localized: $0.title)
            }
            .accessibilityIdentifier("autofill-kind")
            if kind.isPerSpace {
                CrestSpaceMenuPicker(
                    "Space",
                    selection: $pickedSpaceID,
                    spaces: CrestSpaceIdentity.list(browser.spaceModels)
                )
            }
        } footer: {
            if !kind.isPerSpace {
                CrestFormFootnote("Shared with all Spaces.")
            }
        }
    }
}
