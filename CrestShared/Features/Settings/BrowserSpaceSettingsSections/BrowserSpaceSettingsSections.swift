import SwiftUI

/// One Space's settings on touch: browsing, the lock, and deletion. The
/// desktop spreads the same sections over a Space's Settings pages.
///
/// This is a run of `Section`s rather than a `Form`, so the shell's own
/// container holds them.
struct BrowserSpaceSettingsSections: View {
    let browser: BrowserStore
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    /// Where the Space's downloads go, for a shell that lets the person choose.
    var downloads: BrowserSpaceDownloadSettings?
    var dismissKeyboard: @MainActor () -> Void = {}

    var body: some View {
        BrowserSpaceBrowsingSection(
            browser: browser,
            space: space,
            dismissKeyboard: dismissKeyboard
        )

        BrowserSpaceGroupPinnedTabsSection(browser: browser, space: space)

        BrowserSpaceAccessPolicySection(
            browser: browser,
            space: space,
            spaceAccess: spaceAccess
        )

        if let downloads { BrowserSpaceDownloadsSection(settings: downloads) }

        BrowserSpaceDeletionSection(
            browser: browser,
            spaceID: space.id,
            dataDeleter: dataDeleter
        )
    }
}
