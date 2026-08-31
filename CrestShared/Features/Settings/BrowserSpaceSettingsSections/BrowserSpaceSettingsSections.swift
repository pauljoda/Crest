import SwiftUI

/// One Space's settings, as the superset of what the two shells offer.
///
/// The windowed shell showed browsing, downloads, the lock, Crest Passwords and
/// deletion; the compact one showed browsing, the lock and deletion. That was
/// two hand-maintained lists of the same sections in the same order, so it was
/// one list all along with two of its entries conditional — see
/// ``BrowserSpaceSettingsCapabilities`` for which, and why each is the shell's
/// to offer rather than the section's to guess.
///
/// This is a run of `Section`s rather than a `Form`: the shells put a Space's
/// settings in containers they own — a settings page's form on one, a
/// ``BrowserSettingsPane`` on the other — and only the sections were ever
/// shared.
struct BrowserSpaceSettingsSections: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    var capabilities = BrowserSpaceSettingsCapabilities()
    var manageSearchEngines: (() -> Void)? = nil
    var dismissKeyboard: @MainActor () -> Void = {}

    var body: some View {
        BrowserSpaceBrowsingSection(
            browser: browser,
            space: space,
            manageSearchEngines: manageSearchEngines,
            dismissKeyboard: dismissKeyboard
        )

        if let downloads = capabilities.downloads {
            BrowserSpaceDownloadsSection(settings: downloads)
        }

        BrowserSpaceAccessPolicySection(
            browser: browser,
            space: space,
            spaceAccess: spaceAccess
        )

        if capabilities.editsCrestPasswords {
            BrowserSpaceCredentialSyncSection(browser: browser, space: space)
        }

        BrowserSpaceDeletionSection(
            browser: browser,
            spaceID: space.id,
            dataDeleter: dataDeleter
        )
    }
}
