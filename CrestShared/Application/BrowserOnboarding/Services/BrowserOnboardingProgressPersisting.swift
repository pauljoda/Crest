@MainActor
protocol BrowserOnboardingProgressPersisting: AnyObject {
    var hasCompletedSetup: Bool { get }

    func markCompleted()
}
