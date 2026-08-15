import Foundation

enum BrowserSpaceAccessibilityID {
    static func sidebar(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "space-sidebar",
            id: id.rawValue
        )
    }

    static func tabs(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "space-tabs",
            id: id.rawValue
        )
    }
}
