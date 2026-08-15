import Foundation

enum BrowserWindowAccessibilityID {
    static func scene(_ id: BrowserWindowID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "browser-window",
            id: id.rawValue
        )
    }
}
