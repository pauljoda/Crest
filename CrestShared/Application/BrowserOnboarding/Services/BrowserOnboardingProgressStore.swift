import Foundation
import Observation

@Observable
@MainActor
final class BrowserOnboardingProgressStore {
    private(set) var isLaunchGateActive: Bool
    private(set) var isChecking: Bool
    private(set) var hasCompletedSetup: Bool

    var shouldPresentWelcome: Bool { isLaunchGateActive }

    @ObservationIgnored private let persistence: any BrowserOnboardingProgressPersisting
    @ObservationIgnored private let forceSetup: Bool

    init(
        persistence: any BrowserOnboardingProgressPersisting,
        forceWelcome: Bool = false,
        forceSetup: Bool = false
    ) {
        self.persistence = persistence
        self.forceSetup = forceSetup
        let completedOnThisInstall = persistence.hasCompletedSetup
        let launchGateIsActive =
            forceWelcome
            || forceSetup
            || !completedOnThisInstall
        isLaunchGateActive = launchGateIsActive
        isChecking = launchGateIsActive
        hasCompletedSetup = completedOnThisInstall && !forceSetup
    }

    func refresh() async {
        if forceSetup {
            hasCompletedSetup = false
            isChecking = false
            return
        }
        let local = persistence.hasCompletedSetup
        // Completing setup is an install-local promise. iCloud may restore a
        // person's Spaces, but that must not silently skip the tutorial and
        // customization flow on a device that has never completed it.
        hasCompletedSetup = local
        isChecking = false
    }

    func markCompleted() {
        isLaunchGateActive = false
        hasCompletedSetup = true
        isChecking = false
        persistence.markCompleted()
    }
}
