import Foundation

extension BrowserPlatformDownloadPreferences {
    // MARK: - Static Variables

    /// A sandboxed Mac reaches a chosen folder again only through a
    /// security-scoped bookmark.
    static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]

    // MARK: - Actions - Naming

    /// The folder's own name, which folder access checks compare against.
    static func displayName(of url: URL) -> String {
        url.lastPathComponent
    }
}
