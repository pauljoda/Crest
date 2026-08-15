import UniformTypeIdentifiers

extension BrowserBookmarkMigrationSource {
    var allowedContentTypes: [UTType] {
        switch self {
        case .htmlBookmarks:
            [.html]
        case .safariBookmarks:
            [.propertyList]
        case .chromeBookmarks:
            [.json, .data]
        case .firefoxBookmarks, .arcSidebar:
            [.json]
        }
    }
}
