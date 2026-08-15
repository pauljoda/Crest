import Foundation

enum BrowserImportApplication: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case arc
    case zen
    case chrome
    case safari
    case firefox

    var id: String { rawValue }

    var name: String {
        switch self {
        case .arc: "Arc"
        case .zen: "Zen"
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .firefox: "Firefox"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .arc: "company.thebrowser.Browser"
        case .zen: "app.zen-browser.zen"
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .firefox: "org.mozilla.firefox"
        }
    }

    var migrationSource: BrowserTabMigrationSource {
        switch self {
        case .arc: .arc
        case .zen: .zen
        case .chrome: .chrome
        case .safari: .safari
        case .firefox: .firefox
        }
    }

    var sourceDescription: String {
        switch self {
        case .arc: "Spaces, tabs, folders, colors, icons, and passwords"
        case .zen: "Spaces, Essentials, pinned tabs, folders, open tabs, and colors"
        case .chrome: "Profiles, bookmarks, open tabs, and passwords"
        case .safari: "Bookmarks, windows, and open tabs"
        case .firefox: "Windows, open tabs, and pinned tabs"
        }
    }

    var supportsPasswordImport: Bool {
        switch self {
        case .arc, .chrome:
            true
        case .zen, .safari, .firefox:
            false
        }
    }

    var sourceSpaceHeaderStyle: BrowserImportSourceSpaceHeaderStyle {
        switch self {
        case .arc:
            .sectionLabel
        case .zen, .chrome, .safari, .firefox:
            .identity
        }
    }
}
