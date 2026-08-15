@MainActor
final class InMemoryBrowserOnboardingProgressPersistence:
    BrowserOnboardingProgressPersisting
{
    private(set) var hasCompletedSetup: Bool

    init(hasCompletedSetup: Bool = false) {
        self.hasCompletedSetup = hasCompletedSetup
    }

    func markCompleted() {
        hasCompletedSetup = true
    }
}
