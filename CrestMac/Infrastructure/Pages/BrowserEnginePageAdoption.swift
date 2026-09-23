import Foundation

/// A page the engine created itself — a renderer popup, an extension's
/// `windows.create` tab — offered to a window's pool to keep as a tab.
struct BrowserEnginePageAdoption {
    /// The engine's one-shot name for the offered page.
    let token: String
    let profileID: UUID
    /// The engine's name for the page that opened it, when one did.
    let sourcePageID: String?
    /// The window the engine created the page for, when no page opened it.
    let windowID: BrowserWindowID?
    /// The Space that window was opened for.
    let spaceID: SpaceID?
    let url: URL?
    let foreground: Bool
}
