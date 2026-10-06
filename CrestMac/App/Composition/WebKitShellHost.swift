import AppKit

/// What Crest's Mac shell asks of WebKit, which needs nothing of it: WebKit's
/// pages live in Crest's own process and go with their windows, its key
/// equivalents reach Crest's menus through AppKit, and it has no extension
/// shortcuts or extensions an import could bring.
@MainActor
final class WebKitShellHost: BrowserMacEngineHost {
    // MARK: - Variables

    var aboutCredits: String? { nil }
    var importedExtensionInstaller: (any BrowserImportedExtensionInstalling)? { nil }

    // MARK: - Actions - Windows

    func windowClosed(_ windowID: UUID, releasingProfiles profileIDs: [UUID]) {}

    // MARK: - Actions - Shortcuts

    func handleUnclaimedShortcut(_ event: NSEvent, page: BrowserPage) -> Bool { false }
}
