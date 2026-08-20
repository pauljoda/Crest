import SwiftUI

/// The desktop's Spaces pane: the Space list beside the editor for the one
/// picked, and a route in from elsewhere in the app.
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
