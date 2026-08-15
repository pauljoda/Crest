import Foundation

enum BrowserOnboardingLegacyDraftCleanup {
    static let importDraftKey = "crest.onboarding.import-draft"
    static let manualSetupDraftKey = "crest.onboarding.manual-setup-draft"

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: importDraftKey)
        defaults.removeObject(forKey: manualSetupDraftKey)
    }
}
