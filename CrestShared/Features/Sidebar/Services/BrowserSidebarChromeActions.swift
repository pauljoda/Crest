import Foundation

/// The presentation the sidebar's chrome asks its shell to put on screen.
///
/// Every field here is a place where the sidebar knows *what* the reader asked
/// for and the shell knows *where* it goes. The windowed shell answers settings
/// and extensions by pointing a separate scene at a Space; the compact shell
/// answers the same taps with sheets over itself. Those arrive as closures
/// rather than behind a protocol — there is no third shell to swap in, only two
/// hosts that bind their own affordances.
///
/// An optional field is an affordance the shell simply does not have: there is
/// no extensions surface on the compact shell and no password sheet on the
/// windowed one, and `nil` says so rather than a closure that does nothing.
///
/// The struct is `@MainActor` because the hosts build it inside a view body.
/// The closure *fields* carry no isolation annotation, exactly like
/// `BrowserSidebarUtilityPlatformActions`: the values bound to them are plain
/// function values a `View` is already holding, and annotating the fields would
/// demand `@Sendable` conversions the hosts cannot give.
@MainActor
struct BrowserSidebarChromeActions {
    /// Opens the Space's own settings, wherever this shell keeps them.
    let presentSpaceSettings: (BrowserSpace) -> Void

    /// Brings the selected Space's history on screen, inline or as a sheet.
    let presentHistory: () -> Void

    /// Opens the Space's extension list. Absent where there is no such surface.
    let presentExtensions: ((BrowserSpace) -> Void)?

    /// Opens the saved-password list. Absent where the sidebar has no route to
    /// it and the reader reaches passwords through settings instead.
    let presentPasswords: (() -> Void)?

    /// Brings the selected Space's archive on screen. Absent where the archive
    /// is one of the inline utility surfaces rather than a sheet of its own.
    let presentArchive: (() -> Void)?

    /// Brings the selected Space's downloads on screen, under the same rule as
    /// `presentArchive`.
    let presentDownloads: (() -> Void)?

    /// Adds a Space and opens it for editing. Absent where the sidebar offers
    /// no create affordance of its own.
    let createSpace: (() -> Void)?

    init(
        presentSpaceSettings: @escaping (BrowserSpace) -> Void,
        presentHistory: @escaping () -> Void,
        presentExtensions: ((BrowserSpace) -> Void)? = nil,
        presentPasswords: (() -> Void)? = nil,
        presentArchive: (() -> Void)? = nil,
        presentDownloads: (() -> Void)? = nil,
        createSpace: (() -> Void)? = nil
    ) {
        self.presentSpaceSettings = presentSpaceSettings
        self.presentHistory = presentHistory
        self.presentExtensions = presentExtensions
        self.presentPasswords = presentPasswords
        self.presentArchive = presentArchive
        self.presentDownloads = presentDownloads
        self.createSpace = createSpace
    }
}
