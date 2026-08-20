import SwiftUI

/// Touch's Spaces pane: one Space at a time, chosen from a picker.
///
/// Nothing on touch routes a particular Space into Settings the way the
/// desktop's sidebar does, so the requested Space arrives and goes unread.
struct BrowserPlatformSpaceSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: SpaceID?
    let requestRevision: Int

    var body: some View {
        MobileSpaceSettingsView(
            browser: browser,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter
        )
    }
}
