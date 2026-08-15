import Foundation

enum BrowserBookmarkMigrationSource: String, CaseIterable, Identifiable, Sendable {
    case htmlBookmarks
    case safariBookmarks
    case chromeBookmarks
    case firefoxBookmarks
    case arcSidebar

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .htmlBookmarks: "Bookmarks HTML"
        case .safariBookmarks: "Safari"
        case .chromeBookmarks: "Chrome or Chromium"
        case .firefoxBookmarks: "Firefox"
        case .arcSidebar: "Arc"
        }
    }

    var importedSpaceName: LocalizedStringResource {
        switch self {
        case .htmlBookmarks: "Imported Bookmarks"
        case .safariBookmarks: "Imported from Safari"
        case .chromeBookmarks: "Imported from Chrome"
        case .firefoxBookmarks: "Imported from Firefox"
        case .arcSidebar: "Imported from Arc"
        }
    }

    var symbol: String {
        switch self {
        case .htmlBookmarks: "book.closed"
        case .safariBookmarks: "safari"
        case .chromeBookmarks: "globe"
        case .firefoxBookmarks: "flame"
        case .arcSidebar: "sidebar.left"
        }
    }

    var accent: SpaceAccent {
        switch self {
        case .htmlBookmarks: .indigo
        case .safariBookmarks: .teal
        case .chromeBookmarks: .orange
        case .firefoxBookmarks: .rose
        case .arcSidebar: .indigo
        }
    }
}
