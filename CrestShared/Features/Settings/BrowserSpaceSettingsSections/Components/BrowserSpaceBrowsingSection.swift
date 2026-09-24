import SwiftUI

/// A Space's search engine, suggestion privacy choice, and current-tab cleanup.
struct BrowserSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let manageSearchEngines: (() -> Void)?
    let dismissKeyboard: @MainActor () -> Void
    let pickerPresentation: BrowserSpaceBrowsingPickerPresentationStyle

    @State private var presentedSearchEngineSheet: BrowserSearchEngineSheet?

    init(
        browser: BrowserStore,
        space: BrowserSpace,
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
        Section("Browsing", systemImage: "globe") {
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

    private var searchProviderBinding: Binding<SearchProvider> {
        browser.browsingPreferenceBinding(\.searchProvider, in: space)
    }

    private var cleanupPolicyBinding: Binding<CurrentTabCleanup> {
        browser.browsingPreferenceBinding(\.currentTabCleanupPolicy, in: space)
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
                BrowserSearchProviderIdentityLabel(provider: provider, profileID: currentSpace.profile.id)
            },
            selectedValue: {
                HStack(spacing: BrowserSpaceBrowsingPickerValueLayout.touch.providerTextSpacing) {
                    BrowserSearchProviderIcon(
                        provider: currentPreferences.searchProvider,
                        profileID: currentSpace.profile.id,
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
                Text(currentPreferences.currentTabCleanupPolicy.title)
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
