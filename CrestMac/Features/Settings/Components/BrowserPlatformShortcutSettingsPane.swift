import SwiftUI

/// The desktop's Shortcuts pane: the rebindable command table, including the
/// commands a Space's extensions contribute.
struct BrowserPlatformShortcutSettingsPane: View {
    let shortcuts: BrowserShortcutStore
    let browser: BrowserStore
    let extensionControllerPool: BrowserExtensionControllerPool
    let requestedSpaceID: SpaceID?
    let requestedExtensionCommand: BrowserExtensionCommandSettingsRoute?
    let requestRevision: Int

    var body: some View {
        BrowserShortcutSettingsView(
            shortcuts: shortcuts,
            browser: browser,
            extensionControllerPool: extensionControllerPool,
            requestedSpaceID: requestedSpaceID,
            requestedExtensionCommand: requestedExtensionCommand,
            requestRevision: requestRevision
        )
    }
}
