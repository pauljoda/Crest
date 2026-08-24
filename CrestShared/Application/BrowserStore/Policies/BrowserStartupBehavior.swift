import Foundation

enum BrowserStartupBehavior: String, CaseIterable, Identifiable, Sendable {
    case lastActiveTab
    case showStartPage

    static let defaultBehavior = BrowserStartupBehavior.showStartPage

    var id: Self { self }

    var title: String {
        switch self {
        case .lastActiveTab:
            "Open Last Active Tab"
        case .showStartPage:
            "Show Start Page"
        }
    }

    var activatesRestoredTab: Bool {
        self == .lastActiveTab
    }
}
