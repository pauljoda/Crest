import SwiftUI

/// Setup and data portability — the pane a reader opens to move Crest, not to use it.
///
/// The shells provide the setup actions they can offer. The shared pane owns their
/// presentation and the common data-portability surface.
struct BrowserAdvancedSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let setupActions: [BrowserAdvancedSetupAction]
    var showsMacOSImportRequirement = false
    /// Opens Feature Flags, where a shell keeps it under this pane.
    var openFeatureFlags: (() -> Void)? = nil

    var body: some View {
        BrowserSettingsPane(.advanced) {
            BrowserSettingsSectionSlot(.setup) {
                BrowserAdvancedSetupSection(setupActions: setupActions)
            }
            // Only a shell that offers Feature Flags here draws the row, and
            // only that shell lists it in Advanced's search.
            if let openFeatureFlags {
                BrowserSettingsSectionSlot(.featureFlagsLink) {
                    Section {
                        Button(action: openFeatureFlags) {
                            LabeledContent(String(localized: BrowserSettingsDestination.featureFlags.title)) {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-featureFlags")
                    }
                }
            }
            BrowserSettingsSectionSlot(.dataPortability) {
                BrowserDataPortabilitySection(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    showsMacOSImportRequirement: showsMacOSImportRequirement
                )
            }
        }
    }
}
