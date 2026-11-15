import Foundation

extension BrowserPlatformDownloadPreferences {
    // MARK: - Static Variables

    /// An iOS bookmark carries the folder access the document picker granted.
    static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withoutUI

    // MARK: - Actions - Naming

    /// The name the Files app shows, which a provider's folder path need not
    /// carry: iCloud Drive's own is `com~apple~CloudDocs`.
    static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
    }
}
