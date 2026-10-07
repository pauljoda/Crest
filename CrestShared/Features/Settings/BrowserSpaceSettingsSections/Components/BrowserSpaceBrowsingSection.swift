import SwiftUI

/// A Space's search engine, suggestion privacy choice, and current-tab cleanup.
struct BrowserSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: SpaceModel
    let manageSearchEngines: (() -> Void)?
    let dismissKeyboard: @MainActor () -> Void
    let pickerPresentation: BrowserSpaceBrowsingPickerPresentationStyle

    @State private var presentedSearchEngineSheet: BrowserSearchEngineSheet?

    init(
        browser: BrowserStore,
        space: SpaceModel,
        manageSearchEngines: (() -> Void)? = nil,
        dismissKeyboard: @escaping @MainActor () -> Void = {},
        pickerPresentation: BrowserSpaceBrowsingPickerPresentationStyle = BrowserPlatformSearchEnginePresentation
            .pickerStyle
    ) {
        self.browser = browser
        self.space = space
        self.manageSearchEngines = manageSearchEngines
        self.dismissKeyboard = dismissKeyboard
        self.pickerPresentation = pickerPresentation
    }

    var body: some View {
        Section {
            searchProviderPicker

            Button("Manage Search Engines…") {
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

            cleanupPolicyPicker

            Button("Archive Now") {
                browser.cleanupCurrentTabs(in: space.id)
            }
            .disabled(currentPreferences.currentTabCleanup == .never)

        } header: {
            Text("Browsing")
        } footer: {
            CrestFormFootnote("Search suggestions send what you type to the search engine.")
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

    private var currentPreferences: BrowsingPreferences {
        space.settings.browsingPreferences
    }

    private var searchProviderBinding: Binding<SearchProvider> {
        browser.browsingPreferenceBinding(\.searchProvider, in: space)
    }

    private var cleanupPolicyBinding: Binding<CurrentTabCleanup> {
        browser.browsingPreferenceBinding(\.currentTabCleanup, in: space)
    }

    private var searchProviderPicker: some View {
        BrowserSpaceBrowsingPreferencePicker(
            title: "Search engine",
            presentation: pickerPresentation,
            selection: searchProviderBinding,
            choices: currentPreferences.availableSearchProviders,
            choiceTitle: { $0.title },
            accessibilityIdentifier: "space-search-provider",
            dismissKeyboard: dismissKeyboard,
            choiceLabel: { provider in
                BrowserSearchProviderIdentityLabel(provider: provider, profileID: space.profileID)
            },
            selectedValue: {
                HStack(spacing: BrowserSpaceBrowsingPickerValueLayout.touch.providerTextSpacing) {
                    BrowserSearchProviderIcon(
                        provider: currentPreferences.searchProvider,
                        profileID: space.profileID,
                        size: BrowserSearchProviderIdentityLabelLayout.touch.iconSize)
                    Text(currentPreferences.searchProvider.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(BrowserSpaceBrowsingPickerValueLayout.touch.providerTitleLineLimit)
                        .minimumScaleFactor(BrowserSpaceBrowsingPickerValueLayout.touch.minimumProviderTitleScale)
                        .allowsTightening(true)
                }
            })
    }

    private var cleanupPolicyPicker: some View {
        BrowserSpaceBrowsingPreferencePicker(
            title: "Archive current tabs",
            presentation: pickerPresentation,
            selection: cleanupPolicyBinding,
            choices: CurrentTabCleanup.all,
            choiceTitle: { String(localized: $0.title) },
            accessibilityIdentifier: "space-tab-cleanup-policy",
            dismissKeyboard: dismissKeyboard,
            choiceLabel: { policy in
                Text(policy.title)
            },
            selectedValue: {
                Text(currentPreferences.currentTabCleanup.title)
                    .foregroundStyle(.secondary)
            })
    }
}

private enum BrowserSearchEngineSheet: String, Identifiable {
    case manager
    var id: String { rawValue }
}

extension CurrentTabCleanup: Identifiable {
    var id: String { name }
}
