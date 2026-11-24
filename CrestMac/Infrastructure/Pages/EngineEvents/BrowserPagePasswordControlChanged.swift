import Foundation

/// Whether an extension controls password saving in the page's profile, as a
/// password manager's does, so Crest leaves passwords and codes to it there.
struct BrowserPagePasswordControlChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let extensionControlsPasswords: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.setPasswordsHandledByExtension(extensionControlsPasswords)
    }
}
