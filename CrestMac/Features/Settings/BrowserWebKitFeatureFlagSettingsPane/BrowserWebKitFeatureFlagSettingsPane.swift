import SwiftUI

struct BrowserWebKitFeatureFlagSettingsPane: View {
    let store: BrowserWebKitFeatureFlagStore

    @State private var filter = BrowserWebKitFeatureFlagFilter()
    @State private var showsResetConfirmation = false

    var body: some View {
        Group {
            if let availabilityFailure = store.availabilityFailure {
                ContentUnavailableView(
                    "Feature Flags Unavailable",
                    systemImage: "flag.slash",
                    description: Text(availabilityFailure)
                )
            } else {
                content
            }
        }
        .confirmationDialog(
            "Reset every WebKit feature flag?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Feature Flags", role: .destructive) {
                store.resetAll()
            }
        } message: {
            Text(
                "Crest will stop overriding WebKit and use the defaults supplied by macOS."
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text(
                "Crest reads this catalog from the WebKit framework installed on this Mac. Feature availability and defaults may change when macOS updates."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if store.requiresRestart {
                Label(
                    "Restart Crest to apply these changes reliably to every page.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("webkit-feature-restart-notice")
            }

            BrowserWebKitFeatureFlagControls(
                filter: $filter,
                statuses: store.availableStatuses,
                categories: store.availableCategories,
                canReset: store.hasOverrides,
                requestReset: { showsResetConfirmation = true }
            )

            BrowserWebKitFeatureFlagList(
                groups: groups,
                searchText: filter.searchText,
                store: store
            )

            Text(resultSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 780, maxHeight: .infinity, alignment: .topLeading)
    }

    private var groups: [BrowserWebKitFeatureFlagGroup] {
        filter.groups(from: store.features, overrides: store.overrides)
    }

    private var resultSummary: String {
        let visibleCount = groups.reduce(0) { $0 + $1.flags.count }
        let overrideCount = store.activeOverrideCount
        return "Showing \(visibleCount) of \(store.features.count) flags · \(overrideCount) changed"
    }
}
