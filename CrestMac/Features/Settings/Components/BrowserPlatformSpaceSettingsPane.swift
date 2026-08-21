import SwiftUI

/// The desktop's Spaces pane: the Space list beside the editor for the one
/// picked, and a route in from elsewhere in the app.
///
/// The chrome around a Space is what still differs between the shells — a
/// toolbar with a section switcher here, a single scrolling pane on touch — so
/// each keeps its own. The sections inside are
/// ``BrowserSpaceSettingsSections``, and this shell asks it for the whole
/// superset.
struct BrowserPlatformSpaceSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: SpaceID?
    let requestRevision: Int

    var body: some View {
        BrowserSpaceSettingsView(
            browser: browser,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            requestedSpaceID: requestedSpaceID,
            requestRevision: requestRevision
        )
    }
}
