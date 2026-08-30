import AppKit

@MainActor
struct BrowserExtensionActionPresentation: Identifiable {
    let id: String
    let displayName: String
    let badgeText: String
    let icon: NSImage?
    let isEnabled: Bool
    let isPinned: Bool
    let isLoading: Bool

    init(
        id: String,
        displayName: String,
        badgeText: String = "",
        icon: NSImage? = nil,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.badgeText = badgeText
        self.icon = icon
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.isLoading = isLoading
    }

    init(action: BrowserExtensionToolbarAction) {
        self.init(
            id: action.id,
            displayName: action.displayName,
            badgeText: action.badgeText,
            icon: action.icon,
            isEnabled: action.isEnabled,
            isPinned: action.isPinned,
            isLoading: action.isPopupLoading
        )
    }
}
