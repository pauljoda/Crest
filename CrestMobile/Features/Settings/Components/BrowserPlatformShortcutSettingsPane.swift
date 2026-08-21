import SwiftUI

/// Touch reads the same rebindable command table the Mac menu bar does, but it
/// has no Shortcuts pane to edit it with yet.
///
/// The mobile shell hands the router no shortcut store, which is what keeps the
/// destination out of its list; this stands in so one router still builds for
/// both shells.
struct BrowserPlatformShortcutSettingsPane: View {
    let shortcuts: BrowserShortcutStore
    let browser: BrowserStore
    let extensionControllerPool: BrowserExtensionControllerPool
    let requestedSpaceID: SpaceID?
    let requestedExtensionCommand: BrowserExtensionCommandSettingsRoute?
    let requestRevision: Int

    var body: some View {
        EmptyView()
    }
}
