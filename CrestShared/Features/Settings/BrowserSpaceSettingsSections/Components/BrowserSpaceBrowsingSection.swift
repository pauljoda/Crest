import SwiftUI

/// A Space's search engine and its current-tab cleanup policy.
///
/// Both shells had written this section out separately, and the copies agreed
/// on every control and differed only in whether the footnote named the Space —
/// and in whether the cleanup button read the live Space or the stale value the
/// view was handed. Both now read live, which is what
/// ``BrowserStore/liveSpace(_:)`` exists for.
struct BrowserSpaceBrowsingSection: View {
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
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }
}
