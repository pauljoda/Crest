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

    var body: some View {
        BrowserSettingsPane(.advanced) {
            BrowserAdvancedSetupSection(setupActions: setupActions)
            BrowserDataPortabilitySection(
                browser: browser,
                spaceAccess: spaceAccess,
                showsExternalBrowserImportControls: false,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
    }
}
