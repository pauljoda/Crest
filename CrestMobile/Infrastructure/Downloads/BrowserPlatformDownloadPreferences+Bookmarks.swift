import Foundation

/// How iPhone and iPad keep a chosen download folder: the bookmark carries
/// the access the document picker granted, and the folder shows by the name
/// the Files app gives it, which a provider's folder path need not carry, as
/// iCloud Drive's `com~apple~CloudDocs` does not.
extension BrowserPlatformDownloadPreferences {
    // MARK: - Static Variables

    static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withoutUI

    // MARK: - Actions - Naming

    static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
    }
}
