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
                "Crest will restore its performance defaults and stop overriding every other WebKit feature."
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserWebKitPerformanceSettings(store: store)

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

private struct BrowserWebKitPerformanceSettings: View {
    @Bindable var store: BrowserWebKitFeatureFlagStore

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                if store.canConfigureAllow120FPS {
                    performanceToggle(
                        "Allow 120 FPS",
                        description:
                            "Let pages use the full refresh rate on ProMotion and other high-refresh-rate displays.",
                        isOn: $store.allows120FPS,
                        identifier: "webkit-performance-allow-120-fps"
                    )
                }

                if store.canConfigureAllow120FPS
                    && store.canConfigureSmoothScroll
                {
                    Divider()
                }

                if store.canConfigureSmoothScroll {
                    performanceToggle(
                        "Smooth Scroll",
                        description:
                            "Use WebKit’s scroll animator for supported scrolling on macOS.",
                        isOn: $store.usesSmoothScroll,
                        identifier: "webkit-performance-smooth-scroll"
                    )
                }
            }
            .padding(CrestSpacing.extraSmall)
        } label: {
            Label("Performance", systemImage: "gauge.with.dots.needle.67percent")
        }
        .accessibilityIdentifier("webkit-performance-settings")
    }

    private func performanceToggle(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Toggle(title, isOn: isOn)
                .accessibilityIdentifier(identifier)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
