import Foundation

enum BrowserMobileAccessibilityID {
    static let progress = "mobile-onboarding-progress"
    static let welcomeContinue = "mobile-onboarding-continue"
    static let featureNext = "mobile-onboarding-feature-next"
    static let close = "mobile-onboarding-close"
    static let back = "mobile-onboarding-back"
    static let manualSetupFinish = "mobile-manual-setup-finish"
    static let macImportReviewFeatures =
        "mobile-onboarding-manual-setup"
    static let spacesFeature = "mobile-onboarding-feature-spaces"
    static let tabsFeature = "mobile-onboarding-feature-tabs"
    static let syncFeatureList = "mobile-onboarding-feature-sync"
    static let macImportContent = "mobile-onboarding-macos-import"
    static let spaceCarousel = "mobile-manual-space-carousel"
    static let customizationPreview =
        "mobile-space-customization-preview"
    static let customizationControls =
        "mobile-space-customization-controls"

    static func spacePreview(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "mobile-manual-space-preview",
            id: id.rawValue
        )
    }

    static func removeSpace(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "mobile-space-remove",
            id: id.rawValue
        )
    }

    static func customizeSpace(_ id: SpaceID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "mobile-space-customize",
            id: id.rawValue
        )
    }
}
