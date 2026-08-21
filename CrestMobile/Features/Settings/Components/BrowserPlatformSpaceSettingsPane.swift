import SwiftUI

/// Touch's Spaces pane: one Space at a time, chosen from a picker.
///
/// Nothing on touch routes a particular Space into Settings the way the
/// desktop's sidebar does, so the requested Space arrives and goes unread.
///
/// The chrome around a Space is what still differs between the shells — a
/// single scrolling pane here, a toolbar with a section switcher on the
/// desktop — so each keeps its own. The sections inside are
/// ``BrowserSpaceSettingsSections``, and this shell takes the subset it can
/// actually offer.
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
