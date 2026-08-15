import Foundation

enum BrowserStartupBehavior: String, CaseIterable, Identifiable, Sendable {
    case lastActiveTab
    // Preserve the legacy raw value so existing preferences migrate without a
    // one-time surprise. The old behavior created a new Start Page; the current
    // behavior leaves the restored selection unloaded until the user chooses it.
    case waitForTabSelection = "showStartPage"

    static let defaultBehavior = BrowserStartupBehavior.waitForTabSelection

    var id: Self { self }

    var title: String {
        switch self {
        case .lastActiveTab:
            "Open Last Active Tab"
        case .waitForTabSelection:
            "Wait for Tab Selection"
        }
    }

    var activatesRestoredTab: Bool {
        self == .lastActiveTab
    }
}
