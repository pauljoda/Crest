import AppKit

/// What the Mac shell asks of the engine that owns the process, beyond what
/// the core already carries: the little only that engine's own host can do.
/// Everything else about windows, menus, launch, reopen, external opens and
/// quit is the shell's, so another engine's product supplies only this.
@MainActor
protocol BrowserMacEngineHost: AnyObject {
    /// What the About panel credits the engine with, or nil for none.
    var aboutCredits: String? { get }

    /// A window closed whose pages go with it: the engine lets go of what it
    /// kept for the window, and of the profiles named, which no other window
    /// can show.
    func windowClosed(_ windowID: UUID, releasingProfiles profileIDs: [UUID])

    /// Offers a key equivalent no Crest command claimed to the engine for
    /// `page`, the page in front, such as an extension's shortcut. Answers
    /// whether the engine took it.
    func handleUnclaimedShortcut(_ event: NSEvent, page: BrowserPage) -> Bool

    /// Whether `space`, with `page` in front, has an extension whose popup
    /// Open Next Extension can open.
    func opensExtensions(in space: SpaceModel, page: BrowserPage?) -> Bool

    /// Opens the popup of the extension after the one whose popup shows in
    /// `window`, the pinned ones from left to right and then the others, or
    /// the first when none shows. After the last, it closes the popup.
    func openNextExtension(in space: SpaceModel, page: BrowserPage?, window: NSWindow?)

    /// What installs the extensions an import brings, or nil for an engine
    /// that runs none.
    var importedExtensionInstaller: (any BrowserImportedExtensionInstalling)? { get }
}
