import SwiftUI

struct MobileSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: BrowserSpace

    var body: some View {
        Section("Browsing") {
            Picker(
                "Search engine",
                selection: browser.browsingPreferenceBinding(
                    \.searchProvider,
                    in: space
                )
            ) {
                ForEach(BrowserSearchProvider.allCases) { provider in
                    BrowserSearchProviderIdentityLabel(provider: provider)
                        .tag(provider)
                }
            }
            .accessibilityIdentifier("space-search-provider")

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
            .disabled(space.browsingPreferences.currentTabCleanupPolicy == .never)

            Text("Eligible tabs remain recoverable from Archive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
