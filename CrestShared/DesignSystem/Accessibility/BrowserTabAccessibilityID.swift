import Foundation

enum BrowserTabAccessibilityID {
    static func row(_ id: TabID) -> String {
        BrowserAccessibilityID.identifier(prefix: "tab", id: id.rawValue)
    }

    static func archivedRow(_ id: TabID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "archived-tab",
            id: id.rawValue
        )
    }
}
