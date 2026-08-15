import Foundation

@MainActor
final class UserDefaultsBrowserOnboardingProgressPersistence:
    BrowserOnboardingProgressPersisting
{
    static let completionKey = "crest.onboarding.completed"

    private let defaults: UserDefaults
    private let completionKey: String

    init(
        defaults: UserDefaults = .standard,
        completionKey: String =
            UserDefaultsBrowserOnboardingProgressPersistence.completionKey
    ) {
        self.defaults = defaults
        self.completionKey = completionKey
    }

    var hasCompletedSetup: Bool {
        defaults.bool(forKey: completionKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: completionKey)
    }
}
