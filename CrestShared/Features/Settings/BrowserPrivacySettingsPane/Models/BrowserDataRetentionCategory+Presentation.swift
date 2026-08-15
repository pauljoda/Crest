import Foundation

extension BrowserDataRetentionCategory {
    var title: String {
        switch self {
        case .history: "History"
        case .archive: "Archived Tabs"
        case .downloads: "Download Records"
        }
    }

    var cleanupDescription: String {
        switch self {
        case .history: "history entries"
        case .archive: "archived tabs"
        case .downloads: "download records"
        }
    }

    var accessibilityIdentifier: String {
        "retention-\(rawValue)-picker"
    }
}
