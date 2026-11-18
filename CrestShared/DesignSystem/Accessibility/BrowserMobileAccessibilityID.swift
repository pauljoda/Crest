import Foundation

enum BrowserMobileAccessibilityID {
    static let progress = "mobile-onboarding-progress"
    static let featureNext = "mobile-onboarding-feature-next"
    static let close = "mobile-onboarding-close"
    static let macImportReviewFeatures =
        "mobile-onboarding-manual-setup"
    static let spacesFeature = "mobile-onboarding-feature-spaces"
    static let tabsFeature = "mobile-onboarding-feature-tabs"
    static let syncFeatureList = "mobile-onboarding-feature-sync"
    static let macImportContent = "mobile-onboarding-macos-import"

    static func removeSpace(_ id: UUID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "mobile-space-remove",
            id: id
        )
    }

}
