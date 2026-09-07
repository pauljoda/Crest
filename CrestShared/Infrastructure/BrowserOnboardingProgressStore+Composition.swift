import Foundation

extension BrowserOnboardingProgressStore {
    static let completionKey =
        UserDefaultsBrowserOnboardingProgressPersistence.completionKey

    convenience init(
        defaults: UserDefaults? = nil,
        forceWelcome: Bool = false,
        forceSetup: Bool = false
    ) {
        let persistence: any BrowserOnboardingProgressPersisting
        if let defaults {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence(
                defaults: defaults
            )
        } else if BrowserLaunchIsolationPolicy.requiresIsolation(.current) {
            persistence = InMemoryBrowserOnboardingProgressPersistence()
        } else {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence()
        }
        self.init(
            persistence: persistence,
            forceWelcome: forceWelcome,
            forceSetup: forceSetup
        )
    }

    static func launchStore(
        isIsolated: Bool,
        forceWelcome: Bool,
        forceSetup: Bool,
        persistentIsolationID: String? = nil
    ) -> BrowserOnboardingProgressStore {
        let persistence: any BrowserOnboardingProgressPersisting
        if isIsolated, let persistentIsolationID,
            let defaults = UserDefaults(
                suiteName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
                    isolationID: persistentIsolationID))
        {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence(defaults: defaults)
        } else if isIsolated {
            persistence = InMemoryBrowserOnboardingProgressPersistence(hasCompletedSetup: true)
        } else {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence()
        }
        return BrowserOnboardingProgressStore(
            persistence: persistence, forceWelcome: forceWelcome, forceSetup: forceSetup)
    }
}
