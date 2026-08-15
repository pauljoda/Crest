import Foundation

enum BrowserManualSetupAccessibilityID {
    static let spacePicker = "manual-setup-space-picker"
    static let addSpace = "manual-setup-add-space"
    static let sidebarPreview = "manual-setup-sidebar-preview"
    static let error = "manual-setup-error"
    static let address = "manual-setup-address"
    static let addTab = "manual-setup-add-tab"

    static func spaceName(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "manual-setup-space-name",
            id: id.rawValue
        )
    }

    static func placement(_ id: TabID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "manual-setup-placement",
            id: id.rawValue
        )
    }

    static func suggestion(
        _ suggestion: BrowserSetupSiteSuggestion
    ) -> String {
        "manual-setup-suggestion-\(BrowserAccessibilityID.urlIdentity(suggestion.id))"
    }
}
