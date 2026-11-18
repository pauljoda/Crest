import Foundation

/// The browser a manual setup would leave once applied, which every page of
/// setup and its live preview draw. It is made again only when the setup
/// changes, as asking the core for it rebuilds every Space.
@MainActor
final class BrowserSetupDraftPreview {
    // MARK: - Variables

    private var made: (draft: SetupDraft, preview: BrowserSessionPreview?)?

    // MARK: - Actions - Reading

    /// The browser `setup` would leave in `browser`, or nil before the setup
    /// starts or where the core cannot apply it.
    func preview(of setup: BrowserManualSetupModel, in browser: BrowserStore) -> BrowserSessionPreview? {
        guard let draft = setup.draft else { return nil }
        if let made, made.draft == draft { return made.preview }
        let preview = try? browser.importPreview(
            ApplyManualSetup(workspaceID: browser.family.workspaceID, windowID: browser.windowID))
        made = (draft, preview)
        return preview
    }
}
