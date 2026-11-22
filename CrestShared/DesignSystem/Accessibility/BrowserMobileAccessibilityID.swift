import Foundation

/// The accessibility identifiers of the iPhone and iPad's own controls.
enum BrowserMobileAccessibilityID {
    // MARK: - Types

    /// The rows of a link route's editor, each named by its route.
    enum LinkRoute {
        static func row(_ id: UUID) -> String { identifier("link-route", id) }
        static func enabled(_ id: UUID) -> String { identifier("route-enabled", id) }
        static func match(_ id: UUID) -> String { identifier("route-match", id) }
        static func pattern(_ id: UUID) -> String { identifier("route-pattern", id) }
        static func destination(_ id: UUID) -> String { identifier("route-destination", id) }
        static func moveUp(_ id: UUID) -> String { identifier("route-move-up", id) }
        static func moveDown(_ id: UUID) -> String { identifier("route-move-down", id) }
        static func delete(_ id: UUID) -> String { identifier("route-delete", id) }

        private static func identifier(_ prefix: String, _ id: UUID) -> String {
            BrowserAccessibilityID.identifier(prefix: prefix, id: id)
        }
    }

    // MARK: - Static Variables

    static let progress = "mobile-onboarding-progress"
    static let featureNext = "mobile-onboarding-feature-next"
    static let close = "mobile-onboarding-close"
    static let macImportReviewFeatures =
        "mobile-onboarding-manual-setup"
    static let spacesFeature = "mobile-onboarding-feature-spaces"
    static let tabsFeature = "mobile-onboarding-feature-tabs"
    static let syncFeatureList = "mobile-onboarding-feature-sync"
    static let macImportContent = "mobile-onboarding-macos-import"

    static let tabViewerButton = "tab-viewer-button"
    static let collapsedDomainChip = "collapsed-domain-chip"
    static let peekOverlay = "mobile-peek-overlay"
    static let quickWindowOverlay = "mobile-quick-window-overlay"
    static let pageActionsMenu = "page-actions-menu"
    static let pageActionsDownloads = "page-actions-downloads"
    static let pageActionsAddToHomeScreen = "page-actions-add-to-home-screen"
    static let allowBlockedAutomaticPopups = "allow-blocked-automatic-popups"

    static let reloadControl = "reload-control"
    static let sidebarToggle = "browser-sidebar-toggle"
    static let sidebarNewTab = "browser-sidebar-new-tab"
    static let privateBrowsingToggle = "private-browsing-toggle"
    static let downloadsButton = "downloads-button"
    static let spaceSettingsButton = "space-settings-button"
    static let emojiIconField = "browser-emoji-icon-field"

    static let spaceCustomize = "mobile-space-customize"
    static let spaceSettingsToolbar = "space-settings-toolbar"
    static let spaceSettingsPicker = "space-settings-picker"
    static let spaceSettingsSectionPicker = "space-settings-section-picker"
    static let spaceSettingsActions = "space-settings-actions"

    // MARK: - Actions - Identifiers

    static func removeSpace(_ id: UUID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "mobile-space-remove",
            id: id
        )
    }

    /// A Space's row in the Space settings list. Its identity is spelled as
    /// Foundation prints it, unlike the lowercased identities elsewhere.
    static func spaceSettingsRow(_ id: UUID) -> String {
        "space-settings-row-\(id)"
    }

    /// The row that opens `destination` in Settings' list.
    static func settingsDestination(_ destination: BrowserSettingsDestination) -> String {
        "settings-\(destination.name)"
    }

    /// The form `destination` shows once it is open.
    static func settingsForm(_ destination: BrowserSettingsDestination) -> String {
        "settings-form-\(destination.name)"
    }
}
