import Foundation

/// Everything the sidebar needs from the page layer, and nothing else.
///
/// The two shells keep their own page stores — one pools windowed cards, the
/// other owns a single compact stack — but the sidebar only ever asks the same
/// handful of questions and issues the same handful of commands. Those live
/// here as closures rather than behind a protocol: there is no second
/// implementation to swap in, only two concrete stores whose matching members
/// each shell binds in its own convenience initializer.
///
/// Every closure reads through its store at call time rather than capturing a
/// snapshot, so Observation still tracks what a row touched — `residencyRevision`
/// in particular exists to be read inside a view body.
@MainActor
struct BrowserSidebarPageAccess {
    /// Whether a tab is holding a resident page, wherever it lives.
    let containsResidentPage: @MainActor (TabID) -> Bool

    /// Whether the resident page a tab holds is the one this Space and profile
    /// own. A stale row asking about a tab that moved gets `false`.
    let containsResidentPageMatching: @MainActor (BrowserTabRuntimeAssignment) -> Bool

    /// The accent a site's own theme color contributes to its favicon.
    let siteThemeIconAccent: @MainActor (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent?

    /// Bumped by the store whenever residency changes. Read it to make a view
    /// depend on residency, which is otherwise invisible to Observation.
    let residencyRevision: @MainActor () -> Int

    /// Brings the session's current selection on screen.
    let selectPages: @MainActor () -> Void

    /// Takes every presented page off screen without evicting it, which is what
    /// a Space returning to its locked state needs.
    let deactivatePagePresentation: @MainActor () -> Void

    /// Releases one tab's resident page, if the Space and profile still own it.
    let unloadPage: @MainActor (TabID, BrowserSpaceRuntimeAssignment) -> Void

    /// Asks a resident page for a fresh favicon. Returns `nil` when the tab has
    /// no page, has moved, or the page cannot produce one.
    let pullFavicon:
        @MainActor (
            TabID,
            BrowserSpaceRuntimeAssignment
        ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?

    /// Shared across both shells already, so the sidebar holds the real thing
    /// rather than a closure over it.
    let downloadCenter: BrowserDownloadCenter
}
