import Foundation

/// How a Mac keeps a chosen download folder: a sandboxed app reaches it again
/// only through a security-scoped bookmark, and shows the folder's own name.
extension BrowserPlatformDownloadPreferences {
    // MARK: - Static Variables

    static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]

    // MARK: - Actions - Naming

    static func displayName(of url: URL) -> String {
        url.lastPathComponent
    }
}
